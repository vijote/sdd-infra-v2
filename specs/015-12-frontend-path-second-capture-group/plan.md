# Architecture Delta: Frontend Path Second Capture Group (Fix Persistent Rewrite-to-/)

**Branch**: `015-12-frontend-path-second-capture-group` | **Date**: 2026-09-26 | **Spec**: [specs/015-12-frontend-path-second-capture-group/spec.md](spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/app-frontend-ingress.yaml` | Modify | Frontend rule: `path: /()(.*?)` (was `/(.*)` — single group, `$2` undefined) so rewrite-target `/$2` is an identity; update comment |
| `terraform/environments/dev/main.tf` | Modify | Bump `apply_app_services_ingress` trigger `manifest_rev` to `"015-12-frontend-second-capture-group"` so the SSM apply re-runs |
| `specs/015-12-frontend-path-second-capture-group/spec.md` | Create | Feature specification |
| `specs/015-12-frontend-path-second-capture-group/plan.md` | Create | This architecture delta |
| `specs/015-12-frontend-path-second-capture-group/tasks.md` | Create | Micro-DAG task graph |
| `specs/015-12-frontend-path-second-capture-group/checklists/requirements.md` | Create | Spec quality checklist |

No new Terraform modules. No new AWS resources. No new K8s API objects. `/api(/|$)(.*)` rule unchanged.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: Unchanged
- **Cluster Control Plane & Core Addons**: Unchanged
- **Platform Services**: ingress-nginx — same Ingress object; both paths now provide capture group 2
- **Application Workloads**: `app-frontend` — assets served with correct Content-Type; unknown paths 404; `app-backend` routing unchanged
- **Shared Dependencies**: `apply_app_services_ingress` (015-10) is the only apply path for this manifest

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Manifest**: Edit frontend path rule in `app-frontend-ingress.yaml`
2. **Stage 2 - Trigger**: Bump `manifest_rev` in `apply_app_services_ingress` (015-10 resource; SSM apply re-runs on trigger change)
3. **Stage 3 - Validation**: `terraform fmt -check -recursive && terraform validate` (CI applies; user curls live URLs)

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev`
- **Live Asset Check (user-managed)**: `curl -skI https://demo.vijote.dev/assets/index-DaMkeDWv.js | grep -i content-type` → `application/javascript`
- **No-Rewrite Check (user-managed)**: `curl -sk -o /dev/null -w '%{http_code}' https://demo.vijote.dev/definitely-not-a-real-path` → `404`
- **Backend Routing (user-managed)**: `curl -sk https://demo.vijote.dev/api/healthz` → backend contract response
