# Architecture Delta: ECR Image Deploy Pipeline

**Branch**: `012-ecr-image-deploy` | **Date**: 2026-09-23 | **Spec**: [specs/012-ecr-image-deploy/spec.md](spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/variables.tf` | Modify | Add `backend_image_tag` / `frontend_image_tag` (string, default `""`) |
| `terraform/environments/dev/main.tf` | Modify | Extend `apply_app_backend` / `apply_app_frontend_ingress` null_resources: image locals (empty tag → baseline, non-empty → ECR), placeholder substitution, ECR token refresh in SSM command, rollout status; triggers = computed image + control-plane instance ID |
| `terraform/environments/dev/manifests/app-backend.yaml` | Modify | Conditional image swap to `.../backend:%%BACKEND_IMAGE_TAG%%` + `imagePullSecrets: [ecr-pull-secret]` (single placeholder occurrence) |
| `terraform/environments/dev/manifests/app-frontend-ingress.yaml` | Modify | Conditional image swap to `.../frontend:%%FRONTEND_IMAGE_TAG%%` + `imagePullSecrets: [ecr-pull-secret]` (single placeholder occurrence) |
| `.github/workflows/deploy-images.yml` | Create | `workflow_dispatch` with optional `backend_image_tag` / `frontend_image_tag` inputs; OIDC role-chaining; sets `TF_VAR_backend_image_tag` / `TF_VAR_frontend_image_tag`; runs terraform apply |

No new Terraform modules. No new AWS resources. No new K8s API objects (secret already exists from 011/014; recreated in-place by the deploy script).

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: Unchanged. Reuses existing control-plane instance, SSM parameters, ECR repos (010), OIDC role-chaining (`AWS_BOOTSTRAP_ROLE_ARN` → `AWS_TERRAFORM_ROLE`).
- **Cluster Control Plane & Core Addons**: Unchanged. kubectl remains control-plane-only; no API server exposure.
- **Platform Services**: Unchanged (ingress-nginx, cert-manager untouched).
- **Application Workloads**: `app-backend` / `app-frontend` Deployments in `sdd-apps` swap to ECR images when tags provided; `ecr-pull-secret` recreated with fresh ECR token on every deploy run.
- **Shared Dependencies**: K8s 1.28.0 strict decoding (manifests stay on current apiVersions); Terraform `replace()` single-occurrence placeholder rule (014 gotcha); `null_resource` triggers must include control-plane instance ID.

Dependency flow: app repo build → `workflow_dispatch` (PAT `INFRA_PAT`) → `deploy-images.yml` → OIDC → terraform apply → SSM send-command → control-plane kubectl → ECR pull via `ecr-pull-secret`.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: Add variables + extend `apply_app_backend` / `apply_app_frontend_ingress` null_resources; manifest placeholder wiring. Applied via existing `terraform-apply.yml` on push.
2. **Stage 2 - Deploy Workflow**: `deploy-images.yml` dispatched with image tag(s); sets `TF_VAR_*`; terraform apply re-runs only `apply_app_backend` / `apply_app_frontend_ingress` (trigger change).
3. **Stage 3 - Cluster Apply (SSM)**: On control plane: refresh `ecr-pull-secret` (fresh ECR token) → `kubectl apply -f` both manifests → `kubectl rollout status` per deployment with a non-empty tag.
4. **Stage 4 - Workloads**: Pods pull ECR images via refreshed secret; empty-tag app keeps public baseline image and skips rollout wait.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode`
- **Manifest Validation**: `kubectl apply --dry-run=client -f manifests/app-backend.yaml -f manifests/app-frontend-ingress.yaml` (post-substitution, on control plane)
- **Service Rollout**: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` (and `app-frontend` when tag set)
- **Resource Verification**: `kubectl get secret ecr-pull-secret -n sdd-apps` (type `kubernetes.io/dockerconfigjson`); image jsonpath checks per spec AC-004/005
- **Testing Policy**: No validation steps inside workflow definitions; user handles all testing (constitution §6).
