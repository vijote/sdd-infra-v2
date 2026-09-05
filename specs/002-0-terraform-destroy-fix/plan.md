# Architecture Delta: Terraform Destroy Workflow Fix

**Branch**: `002-0-terraform-destroy-fix` | **Date**: 2026-09-05 | **Spec**: specs/002-0-terraform-destroy-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `.github/workflows/terraform-destroy.yml` | Modify | Add `cd terraform/environments/dev` to init/destroy steps; add `-backend-config` (bucket, region) to `terraform init`; replace broken single-step auth with 2-step role chain (bootstrap OIDC → assume role, `role-chaining: true`, no `role-external-id`); add `TF_VAR_state_bucket_name`; remove stale `TF_VAR_github_owner`, `TF_VAR_github_repo`, `TF_VAR_mysql_root_password`, `TF_VAR_mysql_password`; retain `workflow_dispatch` + type-"destroy" confirmation gate |

## 2. Architectural Boundaries & Dependency Flow

- **Reference Pattern**: `terraform-apply.yml` (confirmed passing) — destroy mirrors its working directory, backend config, and 2-step auth structure
- **Auth Chain**: GitHub OIDC → bootstrap role (`AWS_BOOTSTRAP_ROLE_ARN`) → assume role (`AWS_ASSUME_ROLE_ARN`) via `role-chaining: true`; assume role trust policy has no ExternalId condition, so `role-external-id` MUST NOT be set
- **State Backend**: S3 bucket from `TF_VAR_state_bucket_name` (repo var) + region; DynamoDB lock table — provisioned by `001-state-backend`
- **Out of Scope**: No Terraform code changes, no new IAM, no new workflows, no AWS resource changes
- **Manual Gate**: `workflow_dispatch` + type-"destroy" confirmation retained — justified deviation from no-manual-gates policy (destructive teardown must not fire on push)

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Workflow Correction**: Edit `.github/workflows/terraform-destroy.yml` per the File Impact Matrix (single file, all corrections in one pass)
2. **Stage 2 - Verification (CI-only)**: Lint the workflow and verify each contract via grep-based checks in GitHub Actions — no local tooling

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **Workflow Lint**: `actionlint .github/workflows/terraform-destroy.yml` — AC-001
- **Backend Config**: `grep -q 'backend-config="bucket=' .github/workflows/terraform-destroy.yml` — AC-002
- **Working Directory**: `grep -q 'cd terraform/environments/dev' .github/workflows/terraform-destroy.yml` — AC-003
- **Auth Chain**: `grep -q 'role-chaining: true' .github/workflows/terraform-destroy.yml && ! grep -q 'role-external-id' .github/workflows/terraform-destroy.yml` — AC-004
- **State Bucket Var**: `grep -q 'TF_VAR_state_bucket_name' .github/workflows/terraform-destroy.yml` — AC-005
- **No Stale Vars**: `! grep -qE 'TF_VAR_mysql_root_password|TF_VAR_mysql_password|TF_VAR_github_owner|TF_VAR_github_repo' .github/workflows/terraform-destroy.yml` — AC-006
- **Confirmation Gate**: `grep -q 'github.event.inputs.confirm' .github/workflows/terraform-destroy.yml` — AC-007
