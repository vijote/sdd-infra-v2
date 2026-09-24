# Execution Graph (DAG): Ingress Annotations Placement Fix

**Input**: Design documents from `/specs/012-6-ingress-annotations-placement/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

## Stage 1: Terraform Foundations

- [x] T001 [Stage 1: Terraform] Move the `annotations:` block (use-regex + rewrite-target) from `spec:` to `metadata:` in `terraform/environments/dev/manifests/app-frontend-ingress.yaml` (Depends on none)
- [x] T002 [Stage 1: Terraform] Bump `apply_app_frontend_ingress.triggers.manifest_rev` to `"012-6-annotation-placement"` in `terraform/environments/dev/main.tf` (Depends on T001)

## Stage 2: Verification

- [x] T003 [Stage 2: Verification] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` and confirm no `spec.annotations` remains in the manifest (Depends on T002)
- [ ] T004 [Stage 2: Verification] Verify AC-002: `terraform plan -detailed-exitcode` shows only `apply_app_frontend_ingress` trigger update, no destroy (Depends on T003)
- [ ] T005 [Stage 2: Verification] Verify AC-003/AC-004: CI apply green; `kubectl get ingress app-ingress -n sdd-apps -o jsonpath='{.metadata.annotations}'` contains use-regex and rewrite-target (Depends on T004)
- [ ] T006 [Stage 2: Verification] Verify AC-005: `curl -sk https://demo.vijote.dev/api/users` reaches the backend; `curl -sk https://demo.vijote.dev/` serves the frontend (Depends on T005)

## Dependency Notes

- T001→T002 sequential (manifest fix before trigger bump)
- T003–T006 are user-run validation (constitution §6: no testing by the agent)
