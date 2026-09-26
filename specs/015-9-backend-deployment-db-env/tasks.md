# Execution Graph (DAG): Backend Deployment DB Env

**Input**: Design documents from `/specs/015-9-backend-deployment-db-env/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

---

## Stage 1: Terraform

- [x] T001 [Stage 1: Terraform] Add DB env block (`DB_HOST`, `DB_PORT`, `DB_USER`/`DB_PASSWORD` via secretKeyRef `mysql-secret`, `DB_NAME`) to the app-backend container in `terraform/environments/dev/manifests/app-backend.yaml` (Depends on none)
- [x] T002 [Stage 1: Terraform] Bump `manifest_rev` trigger to `"015-9-db-env"` in `terraform/environments/dev/main.tf` (Depends on T001)
- [x] T003 [Stage 1: Terraform] Run `terraform fmt -check -recursive` and `terraform validate` (with `terraform init -backend=false`) in `terraform/environments/dev/` (Depends on T002) — verifies AC-001, AC-002

## Stage 2: Acceptance Validation (user-managed)

- [ ] T004 [Stage 2: Validation] CI apply: app-backend pods start with DB env, no `dial tcp [::1]` in logs (Depends on T003) — verifies AC-005
- [ ] T005 [Stage 2: Validation] Rollout completes 2/2, pods Ready (Depends on T004) — verifies AC-005
