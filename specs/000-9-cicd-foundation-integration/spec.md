# Spec: CI/CD Foundation Integration

**Feature Branch**: `000-9-cicd-foundation-integration` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: GitHub Actions Workflows / OIDC Authentication / CloudFormation Outputs / Repository Variables
- **Target Services / Modules**: GitHub Actions terraform-apply.yml, terraform-destroy.yml, terraform-unlock.yml workflows
- **Security & CI/CD**: GitHub OIDC trust, AWS IAM role chaining, CloudFormation stack outputs

### 1.1 GitHub Actions Workflow Contracts
```yaml
# GitHub Actions Workflow Configuration
name: terraform-apply
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  id-token: write
  contents: read

env:
  AWS_BOOTSTRAP_ROLE_ARN: ${{ vars.AWS_BOOTSTRAP_ROLE_ARN }}
  AWS_ASSUME_ROLE_ARN: ${{ vars.AWS_ASSUME_ROLE_ARN }}
  AWS_REGION: ${{ vars.AWS_REGION }}

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ env.AWS_BOOTSTRAP_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
```

### 1.2 CloudFormation Stack Output Contracts
```yaml
# CloudFormation Stack Outputs
Outputs:
  BootstrapRoleArn:
    Description: ARN of GitHub Actions bootstrap role
    Value: !GetAtt BootstrapRole.Arn
    Export:
      Name: github-oidc-bootstrap-role-BootstrapRoleArn

  AssumeRoleArn:
    Description: ARN of GitHub Actions assume role
    Value: !GetAtt AssumeRole.Arn
    Export:
      Name: github-oidc-assume-role-AssumeRoleArn
```

### 1.3 GitHub Repository Variables Contracts
```bash
# Required GitHub Repository Variables
AWS_BOOTSTRAP_ROLE_ARN=<BootstrapRole ARN from CloudFormation>
AWS_ASSUME_ROLE_ARN=<AssumeRole ARN from CloudFormation>
AWS_REGION=<Target AWS Region>
```

### 1.4 Network & Security Contracts
- **OIDC Trust Relationship**: GitHub Actions OIDC provider with repository-level trust
- **Role Chaining**: Bootstrap role assumes target role with external ID validation
- **Session Duration**: 3600 seconds (1 hour) for GitHub Actions workflow
- **External ID Pattern**: Role ARN used as external ID for security validation

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD workflows:
- [ ] AC-001: GitHub repository variables configured with correct role ARNs (GitHub Actions workflow can access AWS_BOOTSTRAP_ROLE_ARN, AWS_ASSUME_ROLE_ARN, AWS_REGION)
- [ ] AC-002: CloudFormation bootstrap stack deployed successfully (GitHub Actions workflow can deploy stack github-oidc-bootstrap-role without errors)
- [ ] AC-003: CloudFormation assume stack deployed successfully (GitHub Actions workflow can deploy stack github-oidc-assume-role without errors)
- [ ] AC-004: GitHub Actions workflow runs successfully with OIDC authentication (terraform-apply.yml workflow completes with success status)
- [ ] AC-005: Bootstrap role can assume target role with external ID validation (GitHub Actions workflow can perform role chaining without errors)
- [ ] AC-006: GitHub Actions workflow has correct OIDC permissions (workflow has id-token: write, contents: read permissions)
- [ ] AC-007: CloudFormation outputs exported correctly (GitHub Actions workflow can access both export names)

## 3. Assumptions & Technical Constraints

- **CloudFormation Stacks**: Bootstrap role stack must be deployed before assume role stack
- **GitHub Repository**: Repository must have GitHub Actions enabled and OIDC provider configured
- **AWS Region**: Target AWS region must support GitHub Actions OIDC integration
- **IAM Boundaries**: Bootstrap role has minimal permissions (sts:AssumeRole only)
- **Manual Configuration**: GitHub repository variables must be configured manually using CloudFormation outputs
- **Testing Policy**: No unit or E2E test generation - validation performed in GitHub Actions workflows before deployment
- **No Local Tooling Required**: No local AWS CLI, GitHub CLI, or other infrastructure tooling required for validation
- **External Prerequisites**: GitHub OIDC provider must be configured in AWS account before CloudFormation deployment