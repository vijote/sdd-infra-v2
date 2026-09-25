# Architecture Delta: Migrate Bootstrap Quote & Gate Fix

**Branch**: `015-2-migrate-bootstrap-quote-gate-fix` | **Date**: 2026-09-25 | **Spec**: [specs/015-2-migrate-bootstrap-quote-gate-fix/spec.md](../spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/main.tf` | Modify | Restructure `apply_app_backend` SSM command: merge 3 `commands[]` entries into 1 `&&`-chained entry; replace nested-quote `-e` bootstrap with stdin pipe via `kubectl exec -i`; bump `migrate_rev` trigger to `015-2-quote-gate-fix` |

No other files change. No new variables, modules, manifests, or AWS resources.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: unchanged.
- **Cluster Control Plane & Core Addons**: unchanged.
- **Application Workloads**: `apply_mysql` -> (single SSM command): pull-secret refresh -> conditional [DB bootstrap (stdin) -> migrate Job apply -> wait complete] -> Deployment apply -> rollout status. Any `&&` failure aborts the command -> `apply_app_backend` fails -> rollout blocked.
- **Shared Dependencies**: unchanged (`mysql-secret`, `ecr-pull-secret`, `local.backend_image`, SSM Run Command pattern).

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` in CI — trigger bump re-runs `apply_app_backend`.
2. **Stage 2 - SSM Command (single entry, ordered, &&-chained)**:
   a. Refresh `ecr-pull-secret` (existing script).
   b. If `backend_migrate_enabled`: `printf '%s\n' "CREATE DATABASE IF NOT EXISTS sdd_backend; GRANT ALL PRIVILEGES ON sdd_backend.* TO 'sdd_app'@'%'; FLUSH PRIVILEGES;" | kubectl exec -i mysql-0 -n sdd-apps -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'` (idempotent; single quotes live only inside the SSM-side double-quoted string).
   c. Apply `backend-db-migrate.yaml` + `kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s`.
   d. Apply `app-backend.yaml` + `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s`.
3. **Stage 3 - Baseline mode**: `backend_image_tag == ""` -> steps b/c skipped via `if ... fi` inside the chain; Deployment still applied.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate`
- **Bootstrap Success**: no `command not found` in SSM stderr; `USE sdd_backend; SHOW TABLES;` as `sdd_app` exits 0
- **Job Gate**: `kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s`
- **Rollout**: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s`
- **Gate Enforcement**: exactly one `commands[]` entry in `main.tf` (no independent steps)
