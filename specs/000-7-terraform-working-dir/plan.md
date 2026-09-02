# Architecture Delta: Terraform Working Directory Fix

**Branch**: `000-7-terraform-working-dir` | **Date**: 2026-09-02 | **Spec**: `specs/000-7-terraform-working-dir/spec.md`

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `.github/workflows/terraform-apply.yml` | Modify | Add working-directory parameter to all Terraform workflow steps |

## 2. Architectural Boundaries & Dependency Flow

- **CI/CD Layer (GitHub Actions)**: Terraform CLI execution context, working directory configuration
- **Infrastructure Layer**: No changes to AWS resources or Terraform modules
- **Path Resolution**: Module sources and relative paths resolved from `terraform/` directory context
- **Shared Dependencies**: Terraform >=1.5.0, GitHub Actions Ubuntu runner environment

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Working Directory Configuration**: Add `working-directory: ./terraform` parameter to all Terraform workflow steps (init, format check, validate, plan, apply)
2. **Stage 2 - Validation**: Verify workflow executes successfully with proper working directory context and module resolution

## 4. Verification Gates

- **Working Directory Validation**: `cd terraform && terraform init && terraform validate` (local testing)
- **Module Resolution**: `cd terraform && terraform plan -out=tfplan` (verifies module sources resolve correctly)
- **Workflow Execution**: GitHub Actions workflow log shows all Terraform steps complete with exit code 0
- **File Generation**: `terraform/` directory contains expected state files and plan artifacts
- **Path Verification**: No "module not found" or "file not found" errors in workflow execution