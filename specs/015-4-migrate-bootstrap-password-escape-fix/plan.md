# Architecture Delta: Migrate Bootstrap Password Escape Fix

**Branch**: `015-4-migrate-bootstrap-password-escape-fix` | **Date**: 2026-09-25 | **Spec**: [specs/015-4-migrate-bootstrap-password-escape-fix/spec.md](../spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/main.tf` | Modify | Fix HCL escape in base64 payload: `-p\\\"$MYSQL_ROOT_PASSWORD\\\"` -> `-p\"$MYSQL_ROOT_PASSWORD\"`; bump `migrate_rev` trigger to `015-4-password-escape-fix` |

No other files change.

## 2. Architectural Boundaries & Dependency Flow

- Unchanged from 015-3: single `&&`-chained SSM command; control plane sees quote-free base64; pod bash parses the decoded script.
- **The fix**: payload must decode to `-p"$MYSQL_ROOT_PASSWORD"` (plain double quotes, no backslashes) so the pod bash groups the password correctly.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` in CI — trigger bump re-runs `apply_app_backend`.
2. **Stage 2 - SSM Command**: unchanged structure — pull-secret refresh -> conditional [bootstrap (fixed payload) -> Job apply -> wait complete] -> Deployment apply -> rollout status.
3. **Stage 3 - Baseline mode**: unchanged (`if ... fi` skip).

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate`
- **Payload Decode**: base64-decode the payload argument -> must show `-p"$MYSQL_ROOT_PASSWORD"` (no `\` before quotes)
- **Bootstrap Success**: `USE sdd_backend; SHOW TABLES;` as `sdd_app` exits 0
- **Job Gate + Rollout**: `kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s` && `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s`
