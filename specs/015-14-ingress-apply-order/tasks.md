# Tasks: Ingress Apply Order (Passthrough Before API)

**Branch**: `015-14-ingress-apply-order` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Stage 1: Manifest

- [x] T001 [Stage 1: Manifests] In `terraform/environments/dev/manifests/app-frontend-ingress.yaml`, reorder the two Ingress documents: passthrough `app-ingress` FIRST, then `app-ingress-api`; update the 015-13 comment to explain the order rationale (webhook rejects app-ingress-api while the stale app-ingress still claims /api) (no dependencies)

## Stage 2: Trigger

- [x] T002 [Stage 2: Terraform] In `terraform/environments/dev/main.tf`, bump `null_resource.apply_app_services_ingress` trigger `manifest_rev` to `"015-14-ingress-apply-order"` (Depends on T001)

## Stage 3: Validation

- [x] T003 [Stage 3: Validation] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (Depends on T002)
