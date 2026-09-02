# Architecture Delta: Terraform Workflow Fix

**Branch**: `000-6-terraform-workflow-fix` | **Date**: 2026-09-02 | **Spec**: `specs/000-6-terraform-workflow-fix/spec.md`

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `.github/workflows/terraform-apply.yml` | Modify | Fix terraform plan command to separate binary plan generation from JSON conversion |

## 2. Architectural Boundaries & Dependency Flow

- **CI/CD Layer (GitHub Actions)**: Terraform CLI execution, binary plan file handling, jq processing
- **Infrastructure Layer**: No changes to AWS resources or Terraform modules
- **Shared Dependencies**: Terraform >=1.5.0, jq availability on Ubuntu runners

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Workflow Fix**: Modify terraform-apply.yml to separate `terraform plan -out=tfplan` from `terraform show -json tfplan > plan.json`
2. **Stage 2 - Validation**: Verify workflow executes successfully with proper phase detection output

## 4. Verification Gates

- **Workflow Validation**: `terraform plan -out=tfplan && terraform show -json tfplan > plan.json && jq -r '.configuration.root_module.resources | map(.mode) | unique | join(",")' plan.json`
- **Plan File Validity**: `terraform apply -auto-approve tfplan` (dry-run validation)
- **GitHub Actions Execution**: Workflow log shows "Terraform Plan" step completes with exit code 0
- **Output Verification**: `echo "phases=$phases" >> $GITHUB_OUTPUT` successfully writes to GitHub Actions output