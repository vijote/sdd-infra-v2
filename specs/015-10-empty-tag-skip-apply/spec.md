---
name: 015-10-empty-tag-skip-apply
description: Skip the Terraform apply when the dispatched image tag is empty instead of rolling back to the baseline image.
date: 2026-09-26
status: Draft
---

# Spec: Empty Image Tag = Skip Apply (No Baseline Rollback)

**Feature Branch**: `015-10-empty-tag-skip-apply` | **Date**: 2026-09-26 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: None (no new AWS resources)
- **Kubernetes / Cluster Scope**: `app-backend` / `app-frontend` Deployments in `sdd-apps` (existing)
- **Target Services / Modules**: `terraform/environments/dev` root composition; `deploy-images.yml` workflow
- **Security & CI/CD**: Existing OIDC role-chaining; no IAM changes

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Existing variables (unchanged contracts, new semantics):
variable "backend_image_tag"  { type = string, default = "" }  # "" = do NOT touch app-backend
variable "frontend_image_tag" { type = string, default = "" }  # "" = do NOT touch app-frontend

# main.tf locals — NEW semantics (empty = skip, not baseline):
# backend_image  = var.backend_image_tag == "" ? null : "${module.ecr.repository_urls["sdd-k8s-platform/backend"]}:${var.backend_image_tag}"
# frontend_image = var.frontend_image_tag == "" ? null : "${module.ecr.repository_urls["sdd-k8s-platform/frontend"]}:${var.frontend_image_tag}"

# null_resource gating — count-based skip (Deployments only):
# resource "null_resource" "apply_app_backend" {
#   count = var.backend_image_tag == "" ? 0 : 1   # applies backend Deployment manifest only
# }
# resource "null_resource" "apply_app_frontend_ingress" {
#   count = var.frontend_image_tag == "" ? 0 : 1  # applies frontend Deployment manifest only
# }
# NEW always-applied resource (count = 1) applies Service + Ingress manifests on every
# apply so fresh cluster recreations stay complete regardless of tags.
```

Downstream references to these null_resources (e.g., `null_resource.apply_app_backend[0].triggers...`) MUST use index `[0]` or conditional expressions to remain valid when `count = 0`.

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# Manifest split (Deployment vs Service/Ingress) so empty tag skips ONLY the Deployment:
# terraform/environments/dev/manifests/app-backend.yaml        -> Deployment ONLY (Service moved out)
# terraform/environments/dev/manifests/app-backend-service.yaml -> NEW: backend Service (always applied)
# terraform/environments/dev/manifests/app-frontend.yaml        -> NEW: frontend Deployment ONLY
# terraform/environments/dev/manifests/app-frontend-ingress.yaml -> Service + Ingress ONLY (Deployment moved out)
# Service + Ingress manifests are applied on EVERY apply (fresh-cluster completeness).
# When a tag is empty, its Deployment manifest is never re-rendered/applied —
# the in-cluster Deployment keeps its current image (no rollback to nginx:alpine).
```

### 1.3 Data & Storage Contracts
- None. No storage, database, or DNS changes.

### 1.4 Network & Security Contracts
- None. No SG, CNI, or IAM changes.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: `terraform fmt -check -recursive && terraform validate` passes in `terraform/environments/dev`
- [ ] AC-002: `terraform plan` with both tags empty shows **zero** changes for `apply_app_backend` / `apply_app_frontend_ingress` (no baseline rollback, no destroy)
- [ ] AC-003: `terraform plan` with only `backend_image_tag=<sha>` shows changes ONLY in `apply_app_backend` (frontend untouched)
- [ ] AC-004: After dispatch with only `backend_image_tag=<sha>`: `kubectl get deployment app-frontend -n sdd-apps -o jsonpath='{.spec.template.spec.containers[0].image}'` is UNCHANGED (not `nginx:alpine`)
- [ ] AC-005: After dispatch with only `backend_image_tag=<sha>`: `kubectl rollout status deployment/app-backend -n sdd-apps` succeeds with the new ECR image
- [ ] AC-006: `deploy-images.yml` unchanged in contract (optional inputs, empty default `""`)
- [ ] AC-007: Service + Ingress manifests applied on EVERY terraform apply (fresh-cluster completeness): after any apply, `kubectl get ingress app-ingress -n sdd-apps` returns the existing Ingress with host `%%INGRESS_HOST%%` substituted

## 3. Assumptions & Technical Constraints
- **Network CIDRs**: N/A
- **IAM / Security Boundaries**: N/A
- **Storage / Backup Boundaries**: N/A
- **External Prerequisites**: None — reuses existing ECR repos, `ecr-pull-secret`, control-plane SSM path
- **Circular Dependency Prevention**: N/A
- **Testing Policy**: No unit or E2E test generation — validation performed directly against AWS infrastructure using CLI tools
- **Known Gotcha (015-6)**: All private-image workloads MUST set `imagePullSecrets: [{name: ecr-pull-secret}]` — preserved by existing manifest logic when tag is non-empty
- **Known Gotcha (015-7/015-8)**: Job `spec.template` immutable → delete-before-apply, standalone (not mid-pipeline) — unchanged
