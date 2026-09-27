# Architecture Delta: Empty Image Tag = Skip Apply (No Baseline Rollback)

**Branch**: `015-10-empty-tag-skip-apply` | **Date**: 2026-09-26 | **Spec**: [specs/015-10-empty-tag-skip-apply/spec.md](spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/app-backend.yaml` | Modify | Deployment ONLY (Service section moved out) |
| `terraform/environments/dev/manifests/app-backend-service.yaml` | Create | Backend Service (always applied) |
| `terraform/environments/dev/manifests/app-frontend.yaml` | Create | Frontend Deployment ONLY |
| `terraform/environments/dev/manifests/app-frontend-ingress.yaml` | Modify | Service + Ingress ONLY (Deployment section moved out) |
| `terraform/environments/dev/main.tf` | Modify | Count-gate `apply_app_backend` / `apply_app_frontend_ingress` on non-empty tag (Deployment manifests only); NEW always-applied `apply_app_services_ingress` (backend Service + frontend Service/Ingress); drop baseline `nginx:alpine` fallback locals; add pull-secret refresh to frontend command |
| `terraform/environments/dev/variables.tf` | Modify | Update `backend_image_tag` / `frontend_image_tag` descriptions: empty = skip Deployment apply (keep current in-cluster image) |
| `specs/015-10-empty-tag-skip-apply/spec.md` | Create | Feature specification |
| `specs/015-10-empty-tag-skip-apply/plan.md` | Create | This architecture delta |
| `specs/015-10-empty-tag-skip-apply/tasks.md` | Create | Micro-DAG task graph |
| `specs/015-10-empty-tag-skip-apply/checklists/requirements.md` | Create | Spec quality checklist |

No new Terraform modules. No new AWS resources. `.github/workflows/deploy-images.yml` unchanged (already forwards empty inputs as empty `TF_VAR_*`).

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: Unchanged — ECR repos, SSM, EC2 control plane all pre-existing
- **Cluster Control Plane & Core Addons**: Unchanged
- **Platform Services**: Unchanged — ingress-nginx, cert-manager untouched
- **Application Workloads**: `app-backend` / `app-frontend` Deployments — apply is now **opt-in per tag**; empty tag leaves in-cluster image as-is
- **Shared Dependencies**: `module.ecr.repository_urls`, control-plane instance ID in triggers (014/004-10 gotchas preserved)

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Manifest split**: Split Deployment manifests from Service/Ingress manifests (backend + frontend)
2. **Stage 2 - Terraform locals**: Drop baseline-fallback image locals; ECR image + pull secret + port/probe constants become unconditional (only rendered when tag set)
3. **Stage 3 - Resource gating**: Count-gate both Deployment null_resources; NEW always-applied `apply_app_services_ingress` for backend Service + frontend Service/Ingress; rewire depends_on chain (mysql → backend/frontend deployments → services_ingress → provider_ids → ccm)
4. **Stage 4 - Validation**: `terraform fmt -check -recursive && terraform validate` (CI runs apply; user validates cluster)

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev`
- **Plan Semantics (CI)**: With both tags empty → no `apply_app_*` resource changes; with one tag set → only that null_resource updates
- **Cluster Rollout (user-managed)**: `kubectl rollout status deployment/app-backend -n sdd-apps`; frontend image unchanged after backend-only dispatch
