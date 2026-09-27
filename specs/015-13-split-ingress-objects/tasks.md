# Tasks: Split Ingress Objects (API Rewrite vs Frontend Passthrough)

**Branch**: `015-13-split-ingress-objects` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Stage 1: Manifest

- [x] T001 [Stage 1: Manifests] In `terraform/environments/dev/manifests/app-frontend-ingress.yaml`, split the Ingress section: NEW `app-ingress-api` (use-regex + rewrite-target /$2 annotations, single path `/api(/|$)(.*)` ImplementationSpecific -> app-backend:80, tls + host) and repurposed `app-ingress` (NO rewrite annotations, single path `/` Prefix -> app-frontend:80, tls + host); update the 015-12 comment to explain the split rationale (no dependencies)

## Stage 2: Trigger

- [x] T002 [Stage 2: Terraform] In `terraform/environments/dev/main.tf`, bump `null_resource.apply_app_services_ingress` trigger `manifest_rev` to `"015-13-split-ingress-objects"` (Depends on T001)

## Stage 3: Validation

- [x] T003 [Stage 3: Validation] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (Depends on T002)
