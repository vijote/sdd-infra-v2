# Execution Graph (DAG): Backend Port Baseline Fix

**Input**: Design documents from `/specs/012-4-backend-port-baseline-fix/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

---

## Stage 1: Terraform Foundations

- [x] T001 [Stage 1: Terraform] Replace 4 hardcoded `8080` values with `%%BACKEND_PORT%%` (containerPort, readiness `httpGet.port`, liveness `httpGet.port`, Service `targetPort`) in `terraform/environments/dev/manifests/app-backend.yaml` (Depends on none)
- [x] T002 [Stage 1: Terraform] Add local `backend_port = var.backend_image_tag == "" ? "80" : "8080"` to the 012 locals block in `terraform/environments/dev/main.tf` (Depends on none)
- [x] T003 [Stage 1: Terraform] Add `replace(..., "%%BACKEND_PORT%%", local.backend_port)` to the `apply_app_backend` manifest substitution chain in `terraform/environments/dev/main.tf` (Depends on T002)
- [x] T004 [Stage 1: Terraform] Bump `apply_app_backend` `triggers.manifest_rev` from `"012-3-port-8080"` to `"012-4-port-baseline"` in `terraform/environments/dev/main.tf` (Depends on T003)

---

## Stage 2: Verification & Acceptance

- [x] T005 [Stage 2: Verification] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (AC-001) (Depends on T004)
- [x] T006 [Stage 2: Verification] Run `grep -c '%%BACKEND_PORT%%' terraform/environments/dev/manifests/app-backend.yaml` (expect 4) and `grep -c 'containerPort: 8080' terraform/environments/dev/manifests/app-backend.yaml` (expect 0) (AC-002) (Depends on T001)
- [ ] T007 [Stage 2: Verification] Run `terraform console` checks: `local.backend_port` = `"80"` with empty tag and `"8080"` with `backend_image_tag=<sha>` (AC-003, AC-004) (Depends on T004)
- [ ] T008 [Stage 2: Verification] Post-apply (baseline): confirm `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` succeeds (AC-005) (Depends on T005)
- [ ] T009 [Stage 2: Verification] Post-dispatch (tagged): confirm `kubectl get endpoints app-backend -n sdd-apps` shows port 8080 and `curl -sk https://demo.vijote.dev/api` returns the Go app's response (AC-006) (Depends on T008)

---

## Dependency Notes

- T002 → T003 → T004 is a strict chain within `main.tf` (local feeds the replace chain; bump lands last).
- T001 is independent of T002 — both must land before the trigger bump forces the re-run.
- T008–T009 require a real CI apply / dispatch; user-managed per constitution §6.
