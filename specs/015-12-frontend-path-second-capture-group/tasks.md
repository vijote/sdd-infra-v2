# Tasks: Frontend Path Second Capture Group (Fix Persistent Rewrite-to-/)

**Branch**: `015-12-frontend-path-second-capture-group` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Stage 1: Manifest

- [x] T001 [Stage 1: Manifests] In `terraform/environments/dev/manifests/app-frontend-ingress.yaml`, change the frontend rule to `path: /()(.*?)` (was `/(.*)`); update the 015-11 comment to state $2 requires a second capture group and /()(.*?) makes the rewrite an identity (no dependencies)

## Stage 2: Trigger

- [x] T002 [Stage 2: Terraform] In `terraform/environments/dev/main.tf`, bump `null_resource.apply_app_services_ingress` trigger `manifest_rev` to `"015-12-frontend-second-capture-group"` (Depends on T001)

## Stage 3: Validation

- [x] T003 [Stage 3: Validation] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (Depends on T002)
