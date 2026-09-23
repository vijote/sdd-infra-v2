# Execution Graph (DAG): ECR Image Deploy Pipeline

**Input**: Design documents from `/specs/012-ecr-image-deploy/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

---

## Stage 1: Terraform Foundations

- [x] T001 [Stage 1: Terraform] Add `backend_image_tag` and `frontend_image_tag` variables (type string, default `""`) in `terraform/environments/dev/variables.tf`
- [x] T002 [Stage 1: Terraform] Add conditional image locals: empty tag → public baseline image + no `imagePullSecrets`; non-empty tag → ECR URL `891377205721.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/{backend,frontend}:<tag>` + `imagePullSecrets` block, in `terraform/environments/dev/main.tf` (Depends on T001)
- [x] T003 [Stage 1: Terraform] Extend `apply_app_backend` / `apply_app_frontend_ingress` null_resources in `terraform/environments/dev/main.tf` (instead of a new `apply_app_images` — avoids duplicate manifest applies): SSM send-command executes (1) recreate `ecr-pull-secret` with fresh `ecr get-authorization-token` (2) `kubectl apply -f` substituted manifest (3) `kubectl rollout status deployment/app-{backend,frontend} -n sdd-apps --timeout=180s`; triggers = computed image + control-plane instance ID; each `%%...%%` placeholder appears exactly once (assignment line only, `-z`/`== ""` guards per 014 gotcha) (Depends on T002)

---

## Stage 2: Manifests

- [x] T004 [Stage 2: Manifests] Wire `%%BACKEND_IMAGE%%` + `%%BACKEND_PULL_SECRET%%` placeholders into `terraform/environments/dev/manifests/app-backend.yaml` (Depends on T002)
- [x] T005 [Stage 2: Manifests] Wire `%%FRONTEND_IMAGE%%` + `%%FRONTEND_PULL_SECRET%%` placeholders into `terraform/environments/dev/manifests/app-frontend-ingress.yaml` (Depends on T002)

---

## Stage 3: CI/CD Workflow

- [x] T006 [Stage 3: CI/CD] Create `.github/workflows/deploy-images.yml`: `workflow_dispatch` with optional string inputs `backend_image_tag` / `frontend_image_tag`; OIDC role-chaining (`AWS_BOOTSTRAP_ROLE_ARN` → `AWS_TERRAFORM_ROLE`); export `TF_VAR_backend_image_tag` / `TF_VAR_frontend_image_tag`; run terraform init + apply -auto-approve; no validation steps (constitution §6) (Depends on T003, T005)

---

## Stage 4: Verification & Acceptance

- [ ] T007 [Stage 4: Verification] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (AC-001) (Depends on T006)
- [ ] T008 [Stage 4: Verification] Run `terraform plan -detailed-exitcode` and confirm only `apply_app_images` trigger update, no destroy (AC-002) (Depends on T007)
- [ ] T009 [Stage 4: Verification] Confirm `.github/workflows/deploy-images.yml` declares both optional inputs (AC-003) (Depends on T006)
- [ ] T010 [Stage 4: Verification] Post-dispatch cluster checks via SSM on control plane: image jsonpath (AC-004), `imagePullSecrets` jsonpath (AC-005), `kubectl rollout status` (AC-006), empty-tag frontend unchanged (AC-007), `ecr-pull-secret` type `kubernetes.io/dockerconfigjson` (AC-008) (Depends on T008)

---

## Dependency Notes

- T002 is the shared root for both manifests (T004, T005) — they can run in parallel.
- T006 (workflow) blocks on all Terraform + manifest edits.
- T007–T010 are sequential verification gates; T010 requires a real dispatch with a pushed backend tag.
