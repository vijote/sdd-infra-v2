# Spec: Backend Port Align

**Feature Branch**: `012-3-backend-port-align` | **Date**: 2026-09-23 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Align `app-backend` manifest to the Go app's actual listen port (8080); no new AWS resources.
- **Kubernetes / Cluster Scope**: `app-backend` Deployment + Service in `sdd-apps`: containerPort 80 → 8080, probes 80 → 8080, Service targetPort 80 → 8080.
- **Target Services / Modules**: `terraform/environments/dev/manifests/app-backend.yaml` (Deployment + Service sections only).
- **Security & CI/CD**: Unchanged. No IAM/SG changes; ECR pull path verified working (012-2).

### 1.1 Terraform / HCL Resource Contracts
```hcl
# No Terraform changes. The manifest is substituted and applied by the existing
# apply_app_backend null_resource (012). Trigger bump NOT required for this change:
# the manifest file content is read at apply time via file(); a script_rev-style bump
# is NOT needed because the SSM command re-runs only on trigger change — therefore
# apply_app_backend gains a manifest_rev trigger bump to force one re-run:
#   triggers.manifest_rev = "012-3-port-8080"
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# app-backend.yaml — Deployment (containers[0]):
#   ports:
#     - containerPort: 8080
#       name: http
#   readinessProbe:  httpGet: { path: /, port: 8080, ... }   # timings unchanged
#   livenessProbe:   httpGet: { path: /, port: 8080, ... }    # timings unchanged
# app-backend.yaml — Service:
#   ports[0].targetPort: 8080   (service port 80 unchanged — ingress /api upstream unaffected)
# app-frontend-ingress.yaml: UNCHANGED (frontend still nginx baseline on 80)
```

### 1.3 Data & Storage Contracts
- None.

### 1.4 Network & Security Contracts
- No SG changes: pod-to-pod traffic on 8080 is intra-node (flannel VXLAN), already allowed by existing rules.
- Ingress path unchanged: ingress-nginx → Service :80 → targetPort 8080.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: `terraform fmt -check -recursive && terraform validate` passes in `terraform/environments/dev`
- [ ] AC-002: `grep -c 'containerPort: 8080' manifests/app-backend.yaml` returns 1 and `grep -c 'targetPort: 8080' manifests/app-backend.yaml` returns 1
- [ ] AC-003: Post-apply, `kubectl get endpoints app-backend -n sdd-apps` shows an endpoint on port 8080 (not 80)
- [ ] AC-004: Post-apply, `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` succeeds (readiness probe passes on 8080)
- [ ] AC-005: `curl -sk https://demo.vijote.dev/api` returns the Go app's response (not nginx 404)

## 3. Assumptions & Technical Constraints
- **Root cause**: manifest hardcoded nginx scaffold values (port 80); Go app defaults to `PORT=8080` (envconfig default, no required env).
- **App contract**: `GET /` on port 8080 returns 200 (verified via probe behavior + config source).
- **IAM**: Unchanged. No new permissions.
- **Testing Policy**: No validation steps in workflows; user handles all testing (constitution §6).
