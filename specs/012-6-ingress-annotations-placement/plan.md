# Architecture Delta: Ingress Annotations Placement Fix

**Branch**: `012-6-ingress-annotations-placement` | **Date**: 2026-09-23 | **Spec**: [specs/012-6-ingress-annotations-placement/spec.md](spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/app-frontend-ingress.yaml` | Modify | Move `annotations:` (use-regex + rewrite-target) from `spec:` to `metadata:`; remove the misplaced block from `spec` |
| `terraform/environments/dev/main.tf` | Modify | Bump `apply_app_frontend_ingress.triggers.manifest_rev` `"012-5-api-strip"` → `"012-6-annotation-placement"` |

No new Terraform modules. No new AWS resources. No new K8s API objects. `apply_app_backend` untouched (its manifest is valid; no trigger bump needed).

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: Unchanged.
- **Cluster Control Plane & Core Addons**: Unchanged. kubectl remains control-plane-only via SSM.
- **Platform Services**: ingress-nginx receives annotations in the correct location; TLS/cert-manager unchanged.
- **Application Workloads**: Unchanged (backend probes/port from 012-4/012-5 intact).
- **Shared Dependencies**: 014 gotchas (trigger bump for re-run; single `%%INGRESS_HOST%%` occurrence); K8s 1.28.0 strict decoding (annotations are metadata-only).

Dependency flow: terraform apply → `apply_app_frontend_ingress` re-runs (manifest_rev bump) → SSM applies ingress with annotations in `metadata` → strict decoding passes → NGINX reload → `/api/*` strips to root paths.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Manifest Fix**: annotations block moved to `metadata` in `app-frontend-ingress.yaml`.
2. **Stage 2 - Terraform**: `manifest_rev` bump in `main.tf`.
3. **Stage 3 - Cluster Apply**: CI `terraform-apply.yml` on push to `main` → SSM apply succeeds → rollout gates pass.
4. **Stage 4 - Verification**: annotations visible on live object; `/api/users` reaches backend; `/` serves frontend.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (only `apply_app_frontend_ingress` trigger update, no destroy)
- **Manifest Validation**: `grep -A2 'annotations:' manifests/app-frontend-ingress.yaml` shows the block under `metadata:`; no `spec.annotations` remains
- **Service Rollout**: `kubectl rollout status deployment/app-frontend -n sdd-apps --timeout=180s`
- **Resource Verification**: `kubectl get ingress app-ingress -n sdd-apps -o jsonpath='{.metadata.annotations}'` contains both keys; `curl -sk https://demo.vijote.dev/api/users` reaches backend; `curl -sk https://demo.vijote.dev/` serves frontend
- **Testing Policy**: No validation steps inside workflow definitions; user handles all testing (constitution §6).
