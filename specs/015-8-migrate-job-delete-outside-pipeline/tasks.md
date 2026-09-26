# Execution Graph (DAG): Migrate Job Delete Outside Pipeline

**Input**: Design documents from `/specs/015-8-migrate-job-delete-outside-pipeline/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

---

## Stage 1: Terraform

- [x] T001 [Stage 1: Terraform] Restructure the conditional migrate block in `terraform/environments/dev/main.tf`: standalone `kubectl delete job backend-db-migrate -n sdd-apps --ignore-not-found` before the `printf | base64 -d | kubectl apply -f -` pipeline (Depends on none)
- [x] T002 [Stage 1: Terraform] Bump `migrate_rev` trigger to `"015-8-delete-outside-pipeline"` in `terraform/environments/dev/main.tf` (Depends on T001)
- [x] T003 [Stage 1: Terraform] Run `terraform fmt -check -recursive` and `terraform validate` (with `terraform init -backend=false`) in `terraform/environments/dev/` (Depends on T002) — verifies AC-001, AC-002

## Stage 2: Acceptance Validation (user-managed)

- [ ] T004 [Stage 2: Validation] CI apply: no `no objects passed to apply` in SSM stderr; migrate Job recreated with new image (Depends on T003) — verifies AC-005
- [ ] T005 [Stage 2: Validation] Migrate Job reaches `Completed` and Deployment rollout succeeds (Depends on T004) — verifies AC-005
