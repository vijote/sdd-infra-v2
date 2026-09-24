# Execution Graph (DAG): Backend Port Align

**Input**: Design documents from `/specs/012-3-backend-port-align/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

---

## Stage 1: Terraform Foundations

- [x] T001 [Stage 1: Terraform] Change `containerPort: 80` → `8080` and readiness/liveness `httpGet.port: 80` → `8080` in the Deployment section of `terraform/environments/dev/manifests/app-backend.yaml` (Depends on none)
- [x] T002 [Stage 1: Terraform] Change Service `targetPort: 80` → `8080` (service port 80 unchanged) in `terraform/environments/dev/manifests/app-backend.yaml` (Depends on none)
- [x] T003 [Stage 1: Terraform] Add `manifest_rev = "012-3-port-8080"` trigger to `null_resource.apply_app_backend` in `terraform/environments/dev/main.tf` to force one re-run (Depends on T001, T002)

---

## Stage 2: Verification & Acceptance

- [x] T004 [Stage 2: Verification] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (AC-001) (Depends on T003)
- [x] T005 [Stage 2: Verification] Run `grep -c 'containerPort: 8080' terraform/environments/dev/manifests/app-backend.yaml` and `grep -c 'targetPort: 8080' terraform/environments/dev/manifests/app-backend.yaml`; both must return 1 (AC-002) (Depends on T002)
- [ ] T006 [Stage 2: Verification] Run `terraform plan -detailed-exitcode` and confirm only `apply_app_backend` trigger update, no destroy (Depends on T003)
- [ ] T007 [Stage 2: Verification] Post-apply: confirm `kubectl get endpoints app-backend -n sdd-apps` shows an endpoint on port 8080 (AC-003) (Depends on T006)
- [ ] T008 [Stage 2: Verification] Post-apply: confirm `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` succeeds (AC-004) (Depends on T007)
- [ ] T009 [Stage 2: Verification] Confirm `curl -sk https://demo.vijote.dev/api` returns the Go app's response, not nginx 404 (AC-005) (Depends on T008)

---

## Dependency Notes

- T001 and T002 are independent edits to the same file — both must land before T003 (trigger bump forces the re-run that picks them up).
- T007–T009 require a real CI apply; user-managed per constitution §6.
