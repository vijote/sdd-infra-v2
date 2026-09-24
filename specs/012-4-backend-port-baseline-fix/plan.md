# Architecture Delta: Backend Port Baseline Fix

**Branch**: `012-4-backend-port-baseline-fix` | **Date**: 2026-09-23 | **Spec**: [specs/012-4-backend-port-baseline-fix/spec.md](spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/app-backend.yaml` | Modify | Replace 4 hardcoded `8080` values with `%%BACKEND_PORT%%`: `containerPort`, readiness `httpGet.port`, liveness `httpGet.port`, Service `targetPort` (service port 80 unchanged) |
| `terraform/environments/dev/main.tf` | Modify | (a) Add local `backend_port = var.backend_image_tag == "" ? "80" : "8080"`; (b) add `replace(..., "%%BACKEND_PORT%%", local.backend_port)` to the `apply_app_backend` manifest substitution chain; (c) bump `triggers.manifest_rev` `"012-3-port-8080"` → `"012-4-port-baseline"` |

No new Terraform modules. No new AWS resources. No new K8s API objects. `app-frontend-ingress.yaml` unchanged. `apply_app_frontend_ingress` untouched.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: Unchanged. Same ECR repos, SSM parameters, OIDC role-chaining.
- **Cluster Control Plane & Core Addons**: Unchanged. kubectl remains control-plane-only via SSM.
- **Platform Services**: Unchanged (ingress-nginx untouched; `/api` upstream still Service :80).
- **Application Workloads**: `app-backend` port becomes tag-conditional: baseline (nginx:alpine) on 80, ECR Go app on 8080; probes and Service targetPort follow the same value.
- **Shared Dependencies**: 014 gotchas (trigger bump for re-run; multi-occurrence placeholder safe — no guards reference `%%BACKEND_PORT%%`); K8s 1.28.0 strict decoding; 012-2 verified ECR pull path.

Dependency flow: terraform apply → `apply_app_backend` re-runs (manifest_rev bump) → SSM send-command → control plane applies substituted manifest (port per tag) → rollout status gate → endpoints register on the active port → ingress `/api` serves whichever backend is live.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Manifest**: 4 × `8080` → `%%BACKEND_PORT%%` in `app-backend.yaml`.
2. **Stage 2 - Terraform**: `backend_port` local + `replace()` chain entry + `manifest_rev` bump in `main.tf`.
3. **Stage 3 - Cluster Apply**: CI `terraform-apply.yml` on push to `main` (baseline mode: nginx on 80, probes pass); later `deploy-images.yml` dispatch (tagged mode: Go app on 8080).
4. **Stage 4 - Workloads**: Baseline bootstrap succeeds at cluster creation; image deploys roll out on 8080.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (only `apply_app_backend` trigger update, no destroy)
- **Manifest Validation**: `grep -c '%%BACKEND_PORT%%'` = 4; `grep -c 'containerPort: 8080'` = 0
- **Mode Checks**: `terraform console` → `local.backend_port` = `"80"` (empty tag) / `"8080"` (tagged)
- **Service Rollout**: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` (baseline post-apply)
- **Resource Verification**: `kubectl get endpoints app-backend -n sdd-apps` (8080 when tagged); `curl -sk https://demo.vijote.dev/api` returns the Go app's response
- **Testing Policy**: No validation steps inside workflow definitions; user handles all testing (constitution §6).
