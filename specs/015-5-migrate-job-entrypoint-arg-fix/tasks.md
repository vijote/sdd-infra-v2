# Execution Graph (DAG): Migrate Job Entrypoint Arg Fix

**Input**: Design documents from `/specs/015-5-migrate-job-entrypoint-arg-fix/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

---

## Stage 1: Terraform

- [x] T001 [Stage 1: Terraform] Change `command: ["/app/backend", "migrate"]` → `command: ["migrate"]` in `terraform/environments/dev/manifests/backend-db-migrate.yaml` (Depends on none)
- [x] T002 [Stage 1: Terraform] Bump `migrate_rev` trigger to `"015-5-entrypoint-arg"` in `terraform/environments/dev/main.tf` (Depends on T001)
- [x] T003 [Stage 1: Terraform] Run `terraform fmt -check -recursive` and `terraform validate` (with `terraform init -backend=false`) in `terraform/environments/dev/` (Depends on T002) — verifies AC-001, AC-002

## Stage 2: Acceptance Validation (user-managed)

- [ ] T004 [Stage 2: Validation] CI apply re-runs `apply_app_backend`; migrate Job pod reaches `Completed` (Depends on T003) — verifies AC-005
- [ ] T005 [Stage 2: Validation] Deployment rollout succeeds after Job completion (Depends on T004) — verifies AC-005
