# Execution Graph (DAG): API Prefix Strip + Probe Fix

**Input**: Design documents from `/specs/012-5-api-prefix-strip-probe-fix/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

## Stage 1: Terraform Foundations

- [x] T001 [Stage 1: Terraform] Add `nginx.ingress.kubernetes.io/use-regex: "true"` and `nginx.ingress.kubernetes.io/rewrite-target: /$2` annotations to the ingress metadata in `terraform/environments/dev/manifests/app-frontend-ingress.yaml` (Depends on none)
- [x] T002 [Stage 1: Terraform] Replace the backend `/api` Prefix rule with regex path `/api(/|$)(.*)` (pathType ImplementationSpecific) in `terraform/environments/dev/manifests/app-frontend-ingress.yaml` (Depends on T001)
- [x] T003 [Stage 1: Terraform] Change both probe `path:` values from `/` to `%%BACKEND_PROBE_PATH%%` in `terraform/environments/dev/manifests/app-backend.yaml` (Depends on none)
- [x] T004 [Stage 1: Terraform] Add `backend_probe_path` local (empty tag → `/`, tagged → `/healthz`) and its `replace(..., "%%BACKEND_PROBE_PATH%%", ...)` entry to the `apply_app_backend` substitution chain in `terraform/environments/dev/main.tf` (Depends on none)
- [x] T005 [Stage 1: Terraform] Bump `triggers.manifest_rev` to `"012-5-probe-path"` on `apply_app_backend` and to `"012-5-api-strip"` on `apply_app_frontend_ingress` in `terraform/environments/dev/main.tf` (Depends on T001, T002, T003, T004)

## Stage 2: Verification

- [x] T006 [Stage 2: Verification] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` and confirm `grep -c '%%BACKEND_PROBE_PATH%%'` = 2, `grep -c 'rewrite-target'` = 1, `grep -c 'use-regex'` = 1 (Depends on T005)
- [ ] T007 [Stage 2: Verification] Verify AC-001/AC-002: `terraform plan -detailed-exitcode` shows only `manifest_rev` trigger updates on `apply_app_backend` and `apply_app_frontend_ingress`, no destroy (Depends on T006)
- [ ] T008 [Stage 2: Verification] Verify AC-003/AC-004: after CI apply, baseline bootstrap passes probes on `/` and `curl -sk https://demo.vijote.dev/api/users` reaches the backend at `/users` (Depends on T007)
- [ ] T009 [Stage 2: Verification] Verify AC-005: dispatch `Deploy App Images` with a tag and confirm probes pass on `/healthz:8080` and rollout status succeeds (Depends on T008)
- [ ] T010 [Stage 2: Verification] Verify AC-006: `curl -sk https://demo.vijote.dev/` serves the frontend and ingress annotations are present on the live object (Depends on T008)

## Dependency Notes

- T001→T002 sequential (same file, annotations before rule rewrite)
- T003 and T004 are independent roots (different files)
- T005 gates all manifest/Terraform edits (trigger bumps last)
- T006–T010 are user-run validation (constitution §6: no testing by the agent)
