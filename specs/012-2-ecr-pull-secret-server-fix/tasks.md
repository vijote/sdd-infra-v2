# Execution Graph (DAG): ECR Pull Secret Server Fix

**Input**: Design documents from `/specs/012-2-ecr-pull-secret-server-fix/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

---

## Stage 1: Terraform Foundations

- [x] T001 [Stage 1: Terraform] Add host-only registry strip `REGISTRY="${REGISTRY%%/*}"` after the `%%ECR_REGISTRY%%` assignment in `terraform/environments/dev/scripts/create-ecr-pull-secret.sh` so `--docker-server` receives the bare registry host (Depends on none)
- [x] T002 [Stage 1: Terraform] Bump `apply_ecr_pull_secret` `triggers.script_rev` from `"014-guard-fix"` to `"012-2-server-fix"` in `terraform/environments/dev/main.tf` to force one re-run (Depends on T001)

---

## Stage 2: Verification & Acceptance

- [x] T003 [Stage 2: Verification] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (AC-001) (Depends on T002)
- [x] T004 [Stage 2: Verification] Run `grep -c 'REGISTRY="%%ECR_REGISTRY%%"' terraform/environments/dev/scripts/create-ecr-pull-secret.sh` and confirm result is 1 (AC-002) (Depends on T001)
- [ ] T005 [Stage 2: Verification] Run `terraform plan -detailed-exitcode` and confirm only `apply_ecr_pull_secret` `script_rev` trigger update, no destroy (AC-005) (Depends on T002)
- [ ] T006 [Stage 2: Verification] Post-apply (after cluster recreation): decode `ecr-pull-secret` and confirm `auths` key is exactly `891377205721.dkr.ecr.us-east-1.amazonaws.com` (AC-003) (Depends on T005)
- [ ] T007 [Stage 2: Verification] Confirm `kubectl rollout status deployment/app-backend -n sdd-apps` succeeds with ECR image pull (AC-004) (Depends on T006)

---

## Dependency Notes

- T001 → T002 is a strict chain: the trigger bump must land with the script fix so the re-run picks up the corrected script.
- T006–T007 require the user's cluster recreation + a real apply; user-managed per constitution §6.
