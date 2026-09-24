# Architecture Delta: Backend Port Align

**Branch**: `012-3-backend-port-align` | **Date**: 2026-09-23 | **Spec**: [specs/012-3-backend-port-align/spec.md](spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/app-backend.yaml` | Modify | Deployment: `containerPort: 80` → `8080`; readiness/liveness `httpGet.port: 80` → `8080` (timings unchanged). Service: `targetPort: 80` → `8080` (service port 80 unchanged) |
| `terraform/environments/dev/main.tf` | Modify | Add `manifest_rev = "012-3-port-8080"` trigger to `apply_app_backend` to force one re-run (provisioner reads manifest via `file()` at apply time; trigger change forces re-substitution + re-apply) |

No new Terraform modules. No new AWS resources. No new K8s API objects. `app-frontend-ingress.yaml` unchanged (frontend still nginx baseline on 80). `apply_app_frontend_ingress` untouched.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: Unchanged. Same ECR repos, SSM parameters, OIDC role-chaining.
- **Cluster Control Plane & Core Addons**: Unchanged. kubectl remains control-plane-only via SSM.
- **Platform Services**: Unchanged (ingress-nginx untouched; `/api` upstream still Service :80).
- **Application Workloads**: `app-backend` Deployment + Service realigned to container port 8080; probes hit 8080; endpoints move 80 → 8080.
- **Shared Dependencies**: 014 gotchas (trigger bump for re-run); K8s 1.28.0 strict decoding (no apiVersion changes); 012-2 verified ECR pull path (bare-host secret).

Dependency flow: terraform apply → `apply_app_backend` re-runs (manifest_rev bump) → SSM send-command → control plane applies substituted manifest → Deployment rolls pods → readiness probe passes on 8080 → endpoints register → ingress `/api` serves the Go app.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Manifest Align**: Port 80 → 8080 in `app-backend.yaml` (containerPort, probes, Service targetPort).
2. **Stage 2 - Trigger Bump**: `manifest_rev = "012-3-port-8080"` added to `apply_app_backend` triggers.
3. **Stage 3 - Cluster Apply**: CI `terraform-apply.yml` on push to `main`; SSM re-applies the substituted manifest; rollout status gate (180s) must pass.
4. **Stage 4 - Workloads**: Pods become Ready on 8080; ingress `/api` serves the Go app.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (only `apply_app_backend` trigger update, no destroy)
- **Manifest Validation**: `grep -c 'containerPort: 8080'` and `grep -c 'targetPort: 8080'` each return 1
- **Service Rollout**: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s`
- **Resource Verification**: `kubectl get endpoints app-backend -n sdd-apps` shows port 8080; `curl -sk https://demo.vijote.dev/api` returns the Go app's response
- **Testing Policy**: No validation steps inside workflow definitions; user handles all testing (constitution §6).
