# Tasks: Empty Image Tag = Skip Apply (No Baseline Rollback)

**Branch**: `015-10-empty-tag-skip-apply` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Stage 1: Manifest Split

- [x] T001 [Stage 1: Manifests] Split `terraform/environments/dev/manifests/app-frontend-ingress.yaml`: move the frontend Deployment into NEW `terraform/environments/dev/manifests/app-frontend.yaml` (Deployment only, keeps %%FRONTEND_IMAGE%% / %%FRONTEND_PULL_SECRET%% placeholders); leave Service + Ingress (with %%INGRESS_HOST%%) in `app-frontend-ingress.yaml` (no dependencies)
- [x] T002 [Stage 1: Manifests] Split `terraform/environments/dev/manifests/app-backend.yaml`: move the backend Service into NEW `terraform/environments/dev/manifests/app-backend-service.yaml` (Service only); leave Deployment only in `app-backend.yaml` (keeps %%BACKEND_IMAGE%% / %%BACKEND_PULL_SECRET%% / %%BACKEND_PORT%% / %%BACKEND_LIVENESS_PATH%% / %%BACKEND_READINESS_PATH%% placeholders) (Depends on T001)

## Stage 2: Terraform Locals

- [x] T003 [Stage 2: Terraform] Rewrite image locals in `terraform/environments/dev/main.tf` (lines ~598-618): `backend_image` / `frontend_image` become unconditional ECR refs (`${module.ecr.repository_urls[...]}:${var.*_image_tag}`); `*_pull_secret` unconditional `imagePullSecrets` block; `backend_port` = `8080`; liveness/readiness = `/healthz` / `/readyz`; remove `backend_migrate_enabled` conditional (always true inside the gated resource) (Depends on T002)

## Stage 3: Resource Gating & Dependency Rewiring

- [x] T004 [Stage 3: Terraform] Add `count = var.backend_image_tag == "" ? 0 : 1` to `null_resource.apply_app_backend` in `terraform/environments/dev/main.tf`; SSM command applies backend Deployment manifest only (migrate Job + DB create + pull-secret refresh steps unchanged inside) (Depends on T003)
- [x] T005 [Stage 3: Terraform] Add `count = var.frontend_image_tag == "" ? 0 : 1` to `null_resource.apply_app_frontend_ingress` in `terraform/environments/dev/main.tf`; SSM command applies frontend Deployment manifest only; add ecr-pull-secret refresh step (same base64 script pattern as backend command) before the apply (Depends on T004)
- [x] T006 [Stage 3: Terraform] Add NEW always-applied `null_resource.apply_app_services_ingress` in `terraform/environments/dev/main.tf` (count = 1): triggers = {instance_id, ingress_host, manifest_rev}; SSM command applies `app-backend-service.yaml` + `app-frontend-ingress.yaml` (%%INGRESS_HOST%% substituted) then waits for `deployment/ingress-nginx-controller` rollout; depends_on = [apply_cert_manager]; rewire downstream: `apply_app_backend`/`apply_app_frontend_ingress` depend on it, `set_node_provider_ids` depends_on moves from `apply_app_frontend_ingress` to `apply_app_services_ingress` (Depends on T005)

## Stage 4: Variables & Validation

- [x] T007 [Stage 4: Terraform] Update `backend_image_tag` / `frontend_image_tag` descriptions in `terraform/environments/dev/variables.tf`: empty = skip Deployment apply, keep current in-cluster image (Depends on T006)
- [x] T008 [Stage 4: Validation] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (init with `-backend=false` if providers missing) (Depends on T007)
