# Tasks: Ingress Frontend Path Capture (Fix White Page)

**Branch**: `015-11-ingress-frontend-path-capture` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Stage 1: Manifest

- [x] T001 [Stage 1: Manifests] In `terraform/environments/dev/manifests/app-frontend-ingress.yaml`, change the frontend rule to `path: /(.*)` + `pathType: ImplementationSpecific` (was `path: /` + `Prefix`); update the incorrect "frontend / rule unaffected" style comment to state the rewrite is an identity for non-/api paths (no dependencies)

## Stage 2: Trigger

- [x] T002 [Stage 2: Terraform] In `terraform/environments/dev/main.tf`, bump `null_resource.apply_app_services_ingress` trigger `manifest_rev` to `"015-11-frontend-path-capture"` (Depends on T001)

## Stage 3: Validation

- [x] T003 [Stage 3: Validation] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (Depends on T002)
