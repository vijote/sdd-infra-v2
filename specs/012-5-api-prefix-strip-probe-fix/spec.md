# Spec: API Prefix Strip + Probe Fix

**Feature Branch**: `012-5-api-prefix-strip-probe-fix` | **Date**: 2026-09-23 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: (a) Ingress `/api` prefix-strip rewrite so the backend serves root paths (`/users`, `/healthz`); (b) tag-conditional probe path — nginx baseline `/`, Go app `/healthz`; no new AWS resources.
- **Kubernetes / Cluster Scope**: `app-frontend-ingress` (ingress-nginx) annotations + backend path regex; `app-backend` Deployment probe paths.
- **Target Services / Modules**: `terraform/environments/dev/manifests/app-frontend-ingress.yaml`, `terraform/environments/dev/manifests/app-backend.yaml`, `terraform/environments/dev/main.tf` (locals + `apply_app_backend` replace chain + `manifest_rev` bump).
- **Security & CI/CD**: Unchanged. No IAM/SG changes; ECR pull path verified (012-2).

### 1.1 Terraform / HCL Resource Contracts
```hcl
# locals (main.tf):
#   backend_probe_path = var.backend_image_tag == "" ? "/" : "/healthz"
# apply_app_backend replace chain gains one replace():
#   replace(..., "%%BACKEND_PROBE_PATH%%", local.backend_probe_path)
# triggers.manifest_rev = "012-5-probe-path"   # bump from "012-4-port-baseline"
# (backend_image / backend_port / instance_id triggers unchanged)
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# app-frontend-ingress.yaml — metadata annotations (added):
#   nginx.ingress.kubernetes.io/use-regex: "true"
#   nginx.ingress.kubernetes.io/rewrite-target: /$2
# app-frontend-ingress.yaml — backend path rule (replaces current /api Prefix rule):
#   - path: /api(/|$)(.*)
#     pathType: ImplementationSpecific
#     backend:
#       service:
#         name: app-backend
#         port:
#           number: 80
#   (frontend / Prefix rule unchanged; / does not match /api(/|$)(.*) so rewrite is safe)
# Behavior: /api/users -> backend sees GET /users; /api/healthz -> GET /healthz (public too)
#
# app-backend.yaml — probes (tagged mode):
#   readinessProbe:  httpGet: { path: %%BACKEND_PROBE_PATH%%, port: %%BACKEND_PORT%%, ... }
#   livenessProbe:   httpGet: { path: %%BACKEND_PROBE_PATH%%, port: %%BACKEND_PORT%%, ... }
#   (2 occurrences of %%BACKEND_PROBE_PATH%%; no guards reference it — 014 gotcha N/A)
# Behavior:
#   empty tag  -> nginx:alpine on 80,  probes { /, 80 }      (baseline bootstrap)
#   tag=<sha>  -> ECR Go app on 8080,  probes { /healthz, 8080 } (image deploy)
```

### 1.3 Data & Storage Contracts
- None.

### 1.4 Network & Security Contracts
- No SG changes. Ingress-nginx → Service :80 → targetPort (80/8080 per tag) unchanged.
- App contract (backend repo): `GET /healthz` → 200; routes at root (`/users`, ...). Kubelet probes hit the pod directly (bypass ingress rewrite).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: `terraform fmt -check -recursive && terraform validate` passes in `terraform/environments/dev`
- [ ] AC-002: `grep -c '%%BACKEND_PROBE_PATH%%' manifests/app-backend.yaml` returns 2; `grep -c 'rewrite-target' manifests/app-frontend-ingress.yaml` returns 1; `grep -c 'use-regex' manifests/app-frontend-ingress.yaml` returns 1
- [ ] AC-003: `terraform console` (empty tag): `local.backend_probe_path` == "/" ; (tagged): == "/healthz"
- [ ] AC-004: Baseline post-apply: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` succeeds (nginx Ready on 80)
- [ ] AC-005: Tagged post-dispatch: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` succeeds (probes pass on /healthz:8080)
- [ ] AC-006: `curl -sk https://demo.vijote.dev/api/users` reaches the backend (no 404 from path mismatch); `curl -sk https://demo.vijote.dev/` serves the frontend
- [ ] AC-007: `kubectl get ingress -n sdd-apps -o jsonpath='{.items[0].metadata.annotations}'` contains `rewrite-target: /$2` and `use-regex: "true"`

## 3. Assumptions & Technical Constraints
- **Root cause**: probes hardcoded `/` (nginx scaffold); Go app returns 404 on `/` → CrashLoop in tagged mode. Ingress passes `/api/...` through unstripped → app would need `/api`-prefixed routes.
- **App contract**: backend repo serves `GET /healthz` → 200 and routes at root (already implemented).
- **Rewrite scope**: `rewrite-target: /$2` applies ingress-wide; frontend `/` rule unaffected (does not match `/api(/|$)(.*)`).
- **IAM**: Unchanged. No new permissions.
- **Testing Policy**: No validation steps in workflows; user handles all testing (constitution §6).
