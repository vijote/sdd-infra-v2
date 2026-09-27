# Architecture Delta: Ingress Apply Order (Passthrough Before API)

**Branch**: `015-14-ingress-apply-order` | **Date**: 2026-09-26 | **Spec**: [specs/015-14-ingress-apply-order/spec.md](spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/app-frontend-ingress.yaml` | Modify | Reorder documents: passthrough `app-ingress` FIRST, then `app-ingress-api`; update comment |
| `terraform/environments/dev/main.tf` | Modify | Bump `apply_app_services_ingress` trigger `manifest_rev` to `"015-14-ingress-apply-order"` so the SSM apply re-runs |
| `specs/015-14-ingress-apply-order/spec.md` | Create | Feature specification |
| `specs/015-14-ingress-apply-order/plan.md` | Create | This architecture delta |
| `specs/015-14-ingress-apply-order/tasks.md` | Create | Micro-DAG task graph |
| `specs/015-14-ingress-apply-order/checklists/requirements.md` | Create | Spec quality checklist |

No new Terraform modules. No new AWS resources. Object contents unchanged from 015-13 — document order only.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: Unchanged
- **Cluster Control Plane & Core Addons**: Unchanged
- **Platform Services**: ingress-nginx — same two Ingress objects; admission webhook conflict resolved by apply order
- **Application Workloads**: Unchanged — frontend passthrough + backend /api rewrite
- **Shared Dependencies**: `apply_app_services_ingress` (015-10) is the only apply path for this manifest

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Manifest**: Reorder the two Ingress documents in `app-frontend-ingress.yaml`
2. **Stage 2 - Trigger**: Bump `manifest_rev` in `apply_app_services_ingress` (015-10 resource; SSM apply re-runs on trigger change)
3. **Stage 3 - Validation**: `terraform fmt -check -recursive && terraform validate` (CI applies; user curls live URLs)

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev`
- **Apply Success (user-managed)**: `kubectl get ingress -n sdd-apps` shows both objects
- **Live Asset Check (user-managed)**: `curl -skI https://demo.vijote.dev/assets/index-DaMkeDWv.js | grep -i content-type` → `application/javascript`
- **Backend Routing (user-managed)**: `curl -sk https://demo.vijote.dev/api/healthz` → backend contract response
