# Spec: GitHub Variables & AWS Role Chaining

**Feature Branch**: `000-5-github-vars-aws-roles` | **Date**: 2026-09-01 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: GitHub Repository Variables / AWS IAM Role Chaining / OIDC Authentication
- **Kubernetes / Cluster Scope**: Workflow environment variables for all phases
- **Target Services / Modules**: Bootstrap role, Assume role, Region configuration
- **Security & CI/CD**: GitHub repository variables, AWS role chaining, secure credential flow

### 1.1 External Prerequisites & Variable Contracts
```hcl
# GitHub Repository Variables (set manually in repo settings)
variable "aws_bootstrap_role_arn" {
  type        = string
  description = "AWS bootstrap role ARN for initial GitHub OIDC trust (EXTERNAL - must be created via CloudFormation)"
}

variable "aws_assume_role_arn" {
  type        = string
  description = "AWS assume role ARN for role chaining after bootstrap (EXTERNAL - must be created via CloudFormation)"
}

variable "aws_region" {
  type        = string
  description = "AWS region for deployment (from GitHub repository variable)"
  default     = "us-east-1"
}

# NOTE: AWS roles are NOT created by Terraform to avoid circular dependencies
# Roles must be provisioned externally before running Terraform
```

### 1.2 GitHub Actions Workflow Contracts
```yaml
# .github/workflows/terraform-apply.yml (updated)
env:
  AWS_BOOTSTRAP_ROLE_ARN: ${{ vars.AWS_BOOTSTRAP_ROLE_ARN }}
  AWS_ASSUME_ROLE_ARN: ${{ vars.AWS_ASSUME_ROLE_ARN }}
  AWS_REGION: ${{ vars.AWS_REGION }}

jobs:
  apply:
    steps:
      - name: Configure AWS Credentials (Bootstrap)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ env.AWS_BOOTSTRAP_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Assume Target Role
        run: |
          TARGET_ROLE=$(aws sts assume-role \
            --role-arn ${{ env.AWS_ASSUME_ROLE_ARN }} \
            --role-session-name github-actions \
            --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
            --output text)
          read AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "$TARGET_ROLE"
          echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" >> $GITHUB_ENV
          echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" >> $GITHUB_ENV
          echo "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN" >> $GITHUB_ENV
```

### 1.3 Data & Storage Contracts
- **Repository Variables**: AWS_BOOTSTRAP_ROLE_ARN, AWS_ASSUME_ROLE_ARN, AWS_REGION (set in GitHub repo settings)
- **Role Chaining**: Bootstrap role assumes target role with temporary credentials
- **Environment Variables**: All workflows use env context for repository variables

### 1.4 Network & Security Contracts
- **Bootstrap Role**: Limited to sts:AssumeRole on target role only
- **Assume Role**: Full infrastructure permissions for deployment
- **OIDC Trust**: GitHub Actions trust relationship with bootstrap role
- **Session Duration**: 1-hour temporary credentials via role chaining

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Repository variables accessible in workflow (`echo $AWS_REGION | grep -q "us-"`)
- [ ] AC-002: Bootstrap role assumption succeeds (`aws sts get-caller-identity --query Arn --output text | grep -q bootstrap`)
- [ ] AC-003: Target role assumption succeeds (`aws sts get-caller-identity --query Arn --output text | grep -q assume`)
- [ ] AC-004: Role chaining credentials valid (`aws s3 ls s3://sdd-k8s-platform-terraform-state`)
- [ ] AC-005: Workflow uses env context (`grep -q "env:" .github/workflows/terraform-apply.yml`)
- [ ] AC-006: No hardcoded region in workflows (`! grep -r "us-east-1" .github/workflows/`)
- [ ] AC-007: Bootstrap role has minimal permissions (`aws iam get-role-policy --role-name bootstrap-role --policy-name bootstrap-policy --query 'PolicyDocument.Statement[0].Action' --output text | grep -q "sts:AssumeRole"`)

## 3. Assumptions & Technical Constraints
- **Repository Variables**: Must be manually set in GitHub repository settings before workflow execution
- **External Prerequisites**: AWS roles must be created via CloudFormation in `cloudformation/` folder before any workflow execution
- **Circular Dependency Prevention**: Roles required by Terraform are provisioned externally to avoid bootstrap paradox
- **Role Dependencies**: Bootstrap role must have sts:AssumeRole permission on target role
- **Region Configuration**: All AWS CLI commands use $AWS_REGION from repository variables
- **Security Boundaries**: Bootstrap role limited to role assumption only, target role has infrastructure permissions
- **Testing Policy**: No unit or E2E test generation - validation performed directly against AWS infrastructure using CLI tools
- **Provider Versions**: Terraform >= 1.5.0, GitHub Actions latest, AWS CLI v2