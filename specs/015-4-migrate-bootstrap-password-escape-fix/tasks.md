# Execution Graph (DAG): Migrate Bootstrap Password Escape Fix

**Input**: Design documents from `/specs/015-4-migrate-bootstrap-password-escape-fix/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

---

## Stage 1: Terraform Escape Fix

- [x] T001 [Stage 1: Terraform] Fix the base64 payload escape: change `-p\\\"$MYSQL_ROOT_PASSWORD\\\"` to `-p\"$MYSQL_ROOT_PASSWORD\"` inside the `base64encode(...)` call in `terraform/environments/dev/main.tf`
- [x] T002 [Stage 1: Terraform] Bump `migrate_rev` trigger to `"015-4-password-escape-fix"` in `terraform/environments/dev/main.tf` (Depends on T001)
- [x] T003 [Stage 1: Terraform] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (plan/apply in CI only) (Depends on T002)

---

## Stage 2: Acceptance Validation (user-managed, direct cluster CLI)

- [ ] T004 [Stage 2: Validation] Verify AC-002: decode the payload from `aws ssm get-command --command-id <ID> --query 'Commands[0].Parameters.commands'` -> shows `-p"$MYSQL_ROOT_PASSWORD"` with no backslashes (Depends on T003)
- [ ] T005 [Stage 2: Validation] Verify AC-003/AC-004/AC-005: bootstrap exits 0, Job Complete, `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` exits 0 (Depends on T004)
