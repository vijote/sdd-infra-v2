# Architecture Delta: CI Workflow Bootstrap

**Branch**: `001-1-ci-workflow-bootstrap` | **Date**: 2026-09-02 | **Spec**: specs/001-1-ci-workflow-bootstrap/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `.github/workflows/terraform-apply.yml` | Modify | Update workflow with role chaining, remove validation steps, add environment variables |
| GitHub Repository Variables | Create | AWS_REGION, AWS_BOOTSTRAP_ROLE_ARN, AWS_TERRAFORM_ROLE, TF_VAR_state_bucket_name |

## 2. Architectural Boundaries & Dependency Flow

- **CI/CD Layer (GitHub Actions)**: Workflow triggers, environment variables, AWS credentials configuration
- **AWS IAM Layer**: GitHub OIDC bootstrap role, Terraform execution role, role chaining permissions
- **Terraform Layer**: State backend configuration, module instantiation, resource creation
- **Shared Dependencies**: GitHub OIDC provider, AWS IAM roles, pre-existing S3 state bucket

## 3. Provisioning & Rollout Stages

1. **Stage 1 - GitHub Variables Configuration**: Set required repository variables for AWS credentials and Terraform configuration
2. **Stage 2 - Workflow Update**: Modify terraform-apply.yml with role chaining and remove validation steps
3. **Stage 3 - Workflow Testing**: Manual workflow dispatch to verify role chaining and Terraform apply execution