# Spec: Ingress Annotations Placement Fix

**Feature Branch**: `012-6-ingress-annotations-placement` | **Date**: 2026-09-23 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Fix annotation placement in `terraform/environments/dev/manifests/app-frontend-ingress.yaml`; no new AWS resources, no new modules.
- **Root Cause**: 012-5 placed the `annotations:` block under `spec:` instead of `metadata:`. K8s 1.28 strict decoding rejects the apply with `unknown field "spec.annotations"`, so `apply_app_frontend_ingress` fails before any resource is created.
- **Kubernetes / Cluster Scope**: `networking.k8s.io/v1` Ingress in `sdd-apps`; annotations must live in `metadata.annotations` (use-regex + rewrite-target), `spec.rules` unchanged (regex path `/api(/|$)(.*)` stays in spec).

## 2. Technical Contracts

### 2.1 Manifest Contract (`app-frontend-ingress.yaml`)

```yaml
metadata:
  name: app-ingress
  namespace: sdd-apps
  labels:
    app: app-frontend
  annotations:                      # MOVED here from spec
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx           # annotations block REMOVED from here
  ...
```

### 2.2 Terraform Contract (`main.tf`)

- `apply_app_frontend_ingress.triggers.manifest_rev`: `"012-5-api-strip"` → `"012-6-annotation-placement"` (forces SSM re-run; 014 gotcha: trigger bump required for re-execution)
- No variable changes, no new locals, no replace-chain changes.

## 3. Technical Acceptance Criteria

- [ ] AC-001: `terraform fmt -check -recursive` exits 0 in `terraform/environments/dev`
- [ ] AC-002: `terraform plan -detailed-exitcode` shows only `apply_app_frontend_ingress` trigger update, no destroy
- [ ] AC-003: CI `terraform-apply.yml` completes green on push to `main`
- [ ] AC-004: `kubectl get ingress app-ingress -n sdd-apps -o jsonpath='{.metadata.annotations}'` contains `use-regex` and `rewrite-target`
- [ ] AC-005: `curl -sk https://demo.vijote.dev/api/users` reaches the backend (prefix stripped); `curl -sk https://demo.vijote.dev/` serves the frontend

## 4. Assumptions & Constraints

- K8s 1.28.0 strict decoding: annotations are metadata-only; `spec.annotations` is invalid.
- 014 gotcha: exactly one `%%INGRESS_HOST%%` occurrence preserved; no guard references it.
- 012-2/012-4/012-5 behavior (ECR pull, port, probe path) unchanged.
- No testing/validation inside workflow definitions (constitution §6); user validates AC-004/AC-005.
