# Spec: ECR Image Deploy Pipeline

**Feature Branch**: `012-ecr-image-deploy` | **Date**: 2026-09-23 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: ECR image deploy via GitHub Actions workflow_dispatch; no new AWS resources.
- **Kubernetes / Cluster Scope**: `sdd-apps` Deployments `app-backend` / `app-frontend` image swap to ECR + `imagePullSecrets: [ecr-pull-secret]`.
- **Target Services / Modules**: `terraform/environments/dev/main.tf` (extend existing `apply_app_backend` / `apply_app_frontend_ingress` null_resources), `manifests/app-backend.yaml`, `manifests/app-frontend-ingress.yaml`.
- **Security & CI/CD**: Existing OIDC role-chaining (`AWS_TERRAFORM_ROLE`); fine-grained PAT (`actions:write`, this repo) stored as secret `INFRA_PAT` in app repo.

### 1.1 Terraform / HCL Resource Contracts
```hcl
variable "backend_image_tag" {
  type        = string
  description = "Backend image tag (git SHA). Empty = keep public baseline image."
  default     = ""
}
variable "frontend_image_tag" {
  type        = string
  description = "Frontend image tag (git SHA). Empty = keep public baseline image."
  default     = ""
}
# null_resource apply_app_backend / apply_app_frontend_ingress (extended, 012):
#   SSM send-command to control plane:
#   1. Recreate ecr-pull-secret with fresh ECR token (12h expiry, refresh-on-deploy)
#   2. kubectl apply -f <substituted manifest>
#   3. kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s
#      kubectl rollout status deployment/app-frontend -n sdd-apps --timeout=180s
# triggers: backend_image / frontend_image (computed from tags) + control-plane instance id
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# app-backend.yaml (when backend_image_tag != "")
image: 891377205721.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/backend:%%BACKEND_IMAGE_TAG%%
imagePullSecrets:
  - name: ecr-pull-secret
# app-frontend-ingress.yaml (when frontend_image_tag != "")
image: 891377205721.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/frontend:%%FRONTEND_IMAGE_TAG%%
imagePullSecrets:
  - name: ecr-pull-secret
# Empty tag => manifest keeps public baseline image, no imagePullSecrets (Terraform replace() conditional)
```

### 1.3 Data & Storage Contracts
- None. No storage, database, or DNS changes.

### 1.4 Network & Security Contracts
- No new SG rules, no API server exposure. kubectl remains control-plane-only via SSM.
- ECR pull secret: `kubernetes.io/dockerconfigjson`, refreshed on every deploy (documented risk: token may expire between rare deploys; running pods unaffected).
- PAT scope: `actions:write` on this repo only; never committed to this repo.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: `terraform fmt -check -recursive && terraform validate` passes in `terraform/environments/dev`
- [ ] AC-002: `terraform plan -detailed-exitcode` shows only `apply_app_backend` / `apply_app_frontend_ingress` null_resource trigger updates, no destroy
- [ ] AC-003: Deploy workflow `.github/workflows/deploy-images.yml` exists with inputs `backend_image_tag`, `frontend_image_tag` (both optional strings)
- [ ] AC-004: After dispatch with `backend_image_tag=<sha>`: `kubectl get deployment app-backend -n sdd-apps -o jsonpath='{.spec.template.spec.containers[0].image}'` returns ECR URL with `<sha>` tag
- [ ] AC-005: `kubectl get deployment app-backend -n sdd-apps -o jsonpath='{.spec.template.spec.imagePullSecrets[0].name}'` returns `ecr-pull-secret`
- [ ] AC-006: `kubectl rollout status deployment/app-backend -n sdd-apps` returns `successfully rolled out`
- [ ] AC-007: Dispatch with empty `frontend_image_tag` leaves `app-frontend` image unchanged (public baseline)
- [ ] AC-008: `kubectl get secret ecr-pull-secret -n sdd-apps` exists with type `kubernetes.io/dockerconfigjson` post-deploy

## 3. Assumptions & Technical Constraints
- **ECR repos**: `891377205721.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/{backend,frontend}` (010 outputs).
- **IAM**: Deploy role retains existing SSM SendCommand + ECR GetAuthorizationToken permissions; no policy changes.
- **External Prerequisites**: PAT created manually; app repo stores it as `INFRA_PAT` secret.
- **Placeholder rule**: `%%BACKEND_IMAGE_TAG%%` / `%%FRONTEND_IMAGE_TAG%%` each appear exactly once (assignment line only); guards use `-z` checks (014 gotcha).
- **Testing Policy**: No validation steps in workflows; user handles all testing.
