# Spec: Backend Port Baseline Fix

**Feature Branch**: `012-4-backend-port-baseline-fix` | **Date**: 2026-09-23 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Make the backend port conditional on the image tag — nginx baseline → 80, ECR Go app → 8080; no new AWS resources.
- **Kubernetes / Cluster Scope**: `app-backend` Deployment + Service in `sdd-apps`: port becomes `%%BACKEND_PORT%%` (substituted per-tag); fixes broken baseline bootstrap (012-3 hardcoded 8080 → nginx probes fail at cluster creation).
- **Target Services / Modules**: `terraform/environments/dev/manifests/app-backend.yaml`, `terraform/environments/dev/main.tf` (locals + `apply_app_backend` replace chain + `manifest_rev` bump).
- **Security & CI/CD**: Unchanged. No IAM/SG changes; ECR pull path verified (012-2).

### 1.1 Terraform / HCL Resource Contracts
```hcl
# locals (main.tf):
#   backend_port = var.backend_image_tag == "" ? "80" : "8080"
# apply_app_backend replace chain gains one replace():
#   replace(..., "%%BACKEND_PORT%%", local.backend_port)
# triggers.manifest_rev = "012-4-port-baseline"   # bump from "012-3-port-8080"
# (backend_image / instance_id triggers unchanged)
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# app-backend.yaml — 4 occurrences of %%BACKEND_PORT%% (all substituted with the
# SAME value; multi-occurrence is intentional and safe — the 014 gotcha applies
# only to placeholders referenced in guards, and %%BACKEND_PORT%% appears in none):
#   ports:
#     - containerPort: %%BACKEND_PORT%%
#       name: http
#   readinessProbe:  httpGet: { path: /, port: %%BACKEND_PORT%%, ... }
#   livenessProbe:   httpGet: { path: /, port: %%BACKEND_PORT%%, ... }
#   Service ports[0].targetPort: %%BACKEND_PORT%%   (service port 80 unchanged)
# Behavior:
#   empty tag  -> nginx:alpine on 80,  probes on 80  (baseline bootstrap works)
#   tag=<sha>  -> ECR Go app on 8080,  probes on 8080 (image deploy works)
```

### 1.3 Data & Storage Contracts
- None.

### 1.4 Network & Security Contracts
- No SG changes: 8080 traffic is intra-node (flannel VXLAN), already allowed; 80 unchanged.
- Ingress path unchanged: ingress-nginx → Service :80 → targetPort (80 or 8080 per tag).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: `terraform fmt -check -recursive && terraform validate` passes in `terraform/environments/dev`
- [ ] AC-002: `grep -c '%%BACKEND_PORT%%' manifests/app-backend.yaml` returns 4; `grep -c 'containerPort: 8080' manifests/app-backend.yaml` returns 0 (no hardcoded port remains)
- [ ] AC-003: Baseline plan (empty tag): `terraform plan` shows `backend_image = "nginx:alpine"` and the substituted manifest contains `containerPort: 80` (verify via `terraform console` local.backend_port == "80")
- [ ] AC-004: Tagged plan (`backend_image_tag=<sha>`): `terraform console` local.backend_port == "8080" and local.backend_image ends with `:<sha>`
- [ ] AC-005: Post-apply (baseline): `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` succeeds (nginx Ready on 80)
- [ ] AC-006: Post-dispatch (tagged): `kubectl get endpoints app-backend -n sdd-apps` shows port 8080 and `curl -sk https://demo.vijote.dev/api` returns the Go app's response

## 3. Assumptions & Technical Constraints
- **Root cause**: 012-3 hardcoded 8080 unconditionally; baseline bootstrap (nginx on 80) fails probes → `apply_app_backend` Failed at cluster creation.
- **App contract**: Go app listens on 8080 (envconfig default); nginx baseline listens on 80.
- **Dispatch contract**: backend repo dispatch unchanged (`backend_image_tag` only); port derived infra-side from tag emptiness.
- **IAM**: Unchanged. No new permissions.
- **Testing Policy**: No validation steps in workflows; user handles all testing (constitution §6).
