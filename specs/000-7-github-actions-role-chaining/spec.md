# Spec: GitHub Actions Role Chaining

**Feature Branch**: `000-7-github-actions-role-chaining` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: GitHub Actions Workflows / AWS IAM Role Chaining / OIDC Authentication
- **Kubernetes / Cluster Scope**: N/A (CI/CD workflow optimization only)
- **Target Services / Modules**: `.github/workflows/*.yml` workflow files
- **Security & CI/CD**: Native AWS role chaining via aws-actions/configure-aws-credentials@v4

### 1.1 GitHub Actions Workflow Contracts
```yaml
# Role Chaining Configuration
- name: Configure AWS Credentials with Role Chaining
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ env.AWS_BOOTSTRAP_ROLE_ARN }}
    aws-region: ${{ env.AWS_REGION }}
    role-chaining: true
    role-duration-seconds: 3600
    role-session-name: github-actions
    role-external-id: ${{ env.AWS_ASSUME_ROLE_ARN }}

# Environment Variables
env:
  AWS_BOOTSTRAP_ROLE_ARN: ${{ vars.AWS_BOOTSTRAP_ROLE_ARN }}
  AWS_ASSUME_ROLE_ARN: ${{ vars.AWS_ASSUME_ROLE_ARN }}
  AWS_REGION: ${{ vars.AWS_REGION }}
```

### 1.2 CloudFormation IAM Role Contracts
```yaml
# Bootstrap Role - OIDC Trust
AssumeRolePolicyDocument:
  Version: '2012-10-17'
  Statement:
    - Effect: Allow
      Principal:
        Federated: arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
      Action: sts:AssumeRoleWithWebIdentity
      Condition:
        StringEquals:
          token.actions.githubusercontent.com:aud: sts.amazonaws.com

# Assume Role - Chaining Trust
AssumeRolePolicyDocument:
  Version: '2012-10-17'
  Statement:
    - Effect: Allow
      Principal:
        AWS: BOOTSTRAP_ROLE_ARN
      Action: sts:AssumeRole
      Condition:
        StringEquals:
          sts:ExternalId: ASSUME_ROLE_ARN
```

### 1.3 Data & Storage Contracts
- **Repository Variables**: AWS_BOOTSTRAP_ROLE_ARN, AWS_ASSUME_ROLE_ARN, AWS_REGION
- **Role Session Duration**: 3600 seconds (1 hour) for GitHub Actions workflow
- **External ID Pattern**: Role ARN used as external ID for security boundary enforcement

### 1.4 Network & Security Contracts
- **Bootstrap Role**: OIDC trust with GitHub Actions, minimal permissions (sts:AssumeRole only)
- **Assume Role**: Infrastructure deployment permissions, accepts chained role assumption
- **External ID Validation**: Uses assume role ARN as external ID for cross-account security
- **Session Boundary**: 1-hour temporary credentials via native role chaining

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Workflows use role-chaining parameter (`grep -q "role-chaining: true" .github/workflows/*.yml`)
- [ ] AC-002: Workflows use role-external-id parameter (`grep -q "role-external-id" .github/workflows/*.yml`)
- [ ] AC-003: No manual aws sts assume-role commands (`! grep -r "aws sts assume-role" .github/workflows/`)
- [ ] AC-004: Assume role uses external ID condition (`grep -A 5 "sts:ExternalId" cloudformation/github-oidc-roles.yaml`)
- [ ] AC-005: Role session duration configured (`grep -q "role-duration-seconds: 3600" .github/workflows/*.yml`)
- [ ] AC-006: Workflow env context unchanged (`grep -q "env:" .github/workflows/terraform-apply.yml`)
- [ ] AC-007: Role chaining executes successfully in workflow (`aws sts get-caller-identity` returns assume role ARN)

## 3. Assumptions & Technical Constraints
- **CloudFormation Stack**: Existing github-oidc-roles stack with external ID support must be deployed
- **Repository Variables**: GitHub repository variables must be configured (AWS_BOOTSTRAP_ROLE_ARN, AWS_ASSUME_ROLE_ARN, AWS_REGION)
- **GitHub Actions Version**: aws-actions/configure-aws-credentials@v4 or higher with role-chaining support
- **AWS Permissions**: Assume role must include sts:ExternalId condition for security boundary enforcement
- **Session Duration**: 1-hour maximum for GitHub Actions workflow timeout constraints
- **Backward Compatibility**: Must maintain existing env context and repository variable structure
- **Testing Policy**: No unit or E2E test generation - validation performed via GitHub Actions workflow execution and AWS CLI verification
- **Security Model**: Bootstrap role → Assume role with external ID validation replaces manual credential extraction