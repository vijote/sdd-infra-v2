# Architecture Delta: API Prefix Strip + Probe Fix

**Branch**: `012-5-api-prefix-strip-probe-fix` | **Date**: 2026-09-23 | **Spec**: [specs/012-5-api-prefix-strip-probe-fix/spec.md](spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/app-frontend-ingress.yaml` | Modify | Add `nginx.ingress.kubernetes.io/use-regex: "true"` + `nginx.ingress.kubernetes.io/rewrite-target: /$2` annotations; replace backend `/api` Prefix rule with regex path `/api(/|$)(.*)` (pathType ImplementationSpecific); frontend `/` Prefix rule unchanged |
| `terraform/environments/dev/manifests/app-backend.yaml` | Modify | Probes: `path: /` → `%%BACKEND_PROBE_PATH%%` (readiness + liveness, 2 occurrences; port stays `%%BACKEND_PORT%%`) |
| `terraform/environments/dev/main.tf` | Modify | (a) Add local `backend_probe_path = var.backend_image_tag == "" ? "/" : "/healthz"`; (b) add `replace(..., "%%BACKEND_PROBE_PATH%%", local.backend_probe_path)` to the `apply_app_backend` substitution chain; (c) bump `triggers.manifest_rev` `"012-4-port-baseline"` → `"012-5-probe-path"` |

No new Terraform modules. No new AWS resources. No new K8s API objects. `apply_app_frontend_ingress` untouched (its manifest is re-applied as-is; no trigger bump needed — the ingress change rides the next apply via its existing triggers... **correction**: `apply_app_frontend_ingress` re-runs only on trigger change, so it gains `manifest_rev = "012-5-api-strip"` too).

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: Unchanged. Same ECR repos, SSM parameters, OIDC role-chaining.
- **Cluster Control Plane & Core Addons**: Unchanged. kubectl remains control-plane-only via SSM.
- **Platform Services**: ingress-nginx gains regex rewrite on the shared ingress object; TLS/cert-manager unchanged.
- **Application Workloads**: Backend probes become tag-conditional (`/` baseline, `/healthz` tagged); public API surface becomes prefix-stripped (`/api/users` → `/users`).
- **Shared Dependencies**: 014 gotchas (trigger bumps for re-runs; multi-occurrence placeholders safe — no guards reference `%%BACKEND_PROBE_PATH%%`); K8s 1.28.0 strict decoding; 012-2 ECR pull path; 012-4 tag-conditional port.

Dependency flow: terraform apply → `apply_app_frontend_ingress` re-runs (manifest_rev bump) → SSM applies ingress with rewrite → `/api/*` strips to root paths → `apply_app_backend` re-runs (manifest_rev bump) → probes per tag → rollout gate → endpoints register → `/api/users` reaches the backend at `/users`.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Ingress Rewrite**: annotations + regex path in `app-frontend-ingress.yaml`.
2. **Stage 2 - Probe Placeholders**: 2 × `%%BACKEND_PROBE_PATH%%` in `app-backend.yaml`.
3. **Stage 3 - Terraform**: `backend_probe_path` local + replace chain entry + `manifest_rev` bumps on both `apply_app_backend` and `apply_app_frontend_ingress` in `main.tf`.
4. **Stage 4 - Cluster Apply**: CI `terraform-apply.yml` on push to `main` (baseline mode); later `deploy-images.yml` dispatch (tagged mode: probes on `/healthz:8080`).
5. **Stage 5 - Workloads**: Baseline bootstrap succeeds; tagged deploys pass probes; `/api/users` reaches the backend; `/` serves the frontend.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (only trigger updates on the two app null_resources, no destroy)
- **Manifest Validation**: `grep -c '%%BACKEND_PROBE_PATH%%'` = 2; `grep -c 'rewrite-target'` = 1; `grep -c 'use-regex'` = 1
- **Mode Checks**: `terraform console` → `local.backend_probe_path` = `"/"` (empty tag) / `"/healthz"` (tagged)
- **Service Rollout**: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` (both modes)
- **Resource Verification**: `curl -sk https://demo.vijote.dev/api/users` reaches the backend; `curl -sk https://demo.vijote.dev/` serves the frontend; ingress annotations present
- **Testing Policy**: No validation steps inside workflow definitions; user handles all testing (constitution §6).
