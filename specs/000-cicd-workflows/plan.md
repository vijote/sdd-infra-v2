# Architecture Delta: CI/CD Workflows

**Branch**: `000-cicd-workflows` | **Date**: 2026-09-01 | **Spec**: specs/000-cicd-workflows/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `.github/workflows/terraform-apply.yml` | Create | Main infrastructure deployment workflow with OIDC auth |
| `.github/workflows/terraform-destroy.yml` | Create | Infrastructure destruction workflow with confirmation gate |
| `.github/workflows/terraform-unlock.yml` | Create | State emergency unlock workflow for recovery |
| `terraform/backend.tf` | Modify | S3 backend configuration with DynamoDB locking |
| `terraform/variables.tf` | Modify | GitHub OIDC role ARN and state configuration variables |
| `terraform/main.tf` | Modify | Root module with all phase dependencies |
| `specs/000-cicd-workflows/validate.sh` | Create | Post-deployment validation script |

## 2. Architectural Boundaries & Dependency Flow

- **CI/CD Layer (GitHub Actions)**: OIDC authentication, workflow orchestration, artifact management, automated deployment
- **State Management Layer**: S3 bucket with versioning and S3 native locking, centralized backend configuration
- **Infrastructure Orchestration**: Single terraform apply across all phases (001-005), job dependencies with artifact passing
- **Security Boundaries**: GitHub OIDC trust relationship, automated deployment on main push, secret injection
- **Shared Dependencies**: Terraform >=1.5.0, AWS provider, GitHub Actions runners, state backend configuration

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Workflow Setup**: Create GitHub Actions workflows with OIDC authentication and environment protection
2. **Stage 2 - State Backend**: Configure S3 bucket and DynamoDB table for centralized state management
3. **Stage 3 - Validation Gate**: Implement terraform validation, planning, and artifact storage
4. **Stage 4 - Apply Execution**: Single workflow run applying all infrastructure phases with secret injection
5. **Stage 5 - Post-Validation**: Automated validation scripts and output reporting

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode -out=tfplan`
- **State Backend Access**: `aws s3 ls s3://sdd-k8s-platform-terraform-state && aws s3api get-object-lock-configuration --bucket sdd-k8s-platform-terraform-state --key terraform.tfstate --query 'ObjectLockConfiguration.ObjectLockEnabled' --output text | grep Enabled`
- **OIDC Role Assumption**: `aws sts get-caller-identity --query Account --output text`
- **Terraform Apply Success**: `terraform apply -auto-approve tfplan && terraform output -json > outputs.json`
- **Resource Creation**: `terraform output -raw vpc_id && terraform output -raw cluster_endpoint`
- **State Consistency**: `terraform show -json tfplan | jq '.values.root_module.resources | length' | grep -v '^0$'`