# Architecture Delta: GitHub Variables & AWS Role Chaining

**Branch**: `000-5-github-vars-aws-roles` | **Date**: 2026-09-02 | **Spec**: specs/000-5-github-vars-aws-roles/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `.github/workflows/terraform-apply.yml` | Modify | Add env context for repository variables and role chaining steps |
| `.github/workflows/terraform-destroy.yml` | Modify | Add env context for repository variables and role chaining steps |
| `.github/workflows/terraform-unlock.yml` | Modify | Add env context for repository variables and role chaining steps |
| `cloudformation/github-oidc-roles.yaml` | Create | AWS IAM roles for bootstrap and assume role with OIDC trust |
| `specs/000-5-github-vars-aws-roles/setup-instructions.md` | Create | Manual setup guide for repository variables and CloudFormation deployment |
| `README.md` | Modify | Add section about GitHub variables and role chaining setup |

## 2. Architectural Boundaries & Dependency Flow

- **GitHub Variables Layer**: Repository variables (AWS_BOOTSTRAP_ROLE_ARN, AWS_ASSUME_ROLE_ARN, AWS_REGION) as single source of truth
- **AWS IAM Layer**: Bootstrap role (minimal permissions) → Assume role (full infrastructure permissions) with OIDC trust
- **Workflow Authentication Layer**: GitHub Actions OIDC authentication → Bootstrap role assumption → Target role assumption
- **Credential Flow Layer**: Temporary credentials via role chaining with 1-hour session duration
- **Security Boundaries**: Bootstrap role limited to sts:AssumeRole only, target role has infrastructure permissions
- **Shared Dependencies**: GitHub Actions OIDC provider, AWS IAM roles, repository variable configuration

## 3. Provisioning & Rollout Stages

1. **Stage 1 - CloudFormation Deployment**: Create AWS IAM roles (bootstrap and assume) with OIDC trust relationship via CloudFormation
2. **Stage 2 - Repository Variables Setup**: Configure GitHub repository variables (AWS_BOOTSTRAP_ROLE_ARN, AWS_ASSUME_ROLE_ARN, AWS_REGION) in repo settings
3. **Stage 3 - Workflow Updates**: Modify all GitHub Actions workflows to use env context for repository variables
4. **Stage 4 - Role Chaining Implementation**: Add bootstrap role assumption and target role chaining steps to workflows
5. **Stage 5 - Validation**: Test repository variable access, role assumption, and credential validation

## 4. Verification Gates

- **Repository Variables Access**: `echo $AWS_REGION | grep -q "us-"`
- **Bootstrap Role Assumption**: `aws sts get-caller-identity --query Arn --output text | grep -q bootstrap`
- **Target Role Assumption**: `aws sts get-caller-identity --query Arn --output text | grep -q assume`
- **Role Chaining Credentials**: `aws s3 ls s3://sdd-k8s-platform-terraform-state`
- **Workflow Env Context**: `grep -q "env:" .github/workflows/terraform-apply.yml`
- **No Hardcoded Regions**: `! grep -r "us-east-1" .github/workflows/`
- **Bootstrap Role Permissions**: `aws iam get-role-policy --role-name bootstrap-role --policy-name bootstrap-policy --query 'PolicyDocument.Statement[0].Action' --output text | grep -q "sts:AssumeRole"`