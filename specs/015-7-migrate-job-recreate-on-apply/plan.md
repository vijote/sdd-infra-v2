# Architecture Delta: Migrate Job Recreate On Apply

**Branch**: `015-7-migrate-job-recreate-on-apply` | **Date**: 2026-09-26 | **Spec**: [specs/015-7-migrate-job-recreate-on-apply/spec.md](../spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/main.tf` | Modify | Add `kubectl delete job backend-db-migrate -n sdd-apps --ignore-not-found &&` before the migrate Job apply in the `apply_app_backend` SSM command; bump `migrate_rev` → `"015-7-recreate-on-apply"` |

No new files, variables, modules, or AWS resources. `backend-db-migrate.yaml` unchanged.

## 2. Architecture Notes

- **K8s Job immutability**: `spec.template` of an existing Job can never be patched — a new image tag in the Job manifest makes `kubectl apply` fail with `field is immutable` whenever the old Job still exists (TTL window or completed-but-kept).
- **Delete-before-apply**: the migrate Job is stateless and one-shot; recreating it is the correct lifecycle. `--ignore-not-found` makes the delete a no-op on first run, keeping the chain idempotent.
- The delete runs inside the existing conditional migrate block, so the `&&` gate semantics are unchanged: any failure still blocks the Deployment apply.

## 3. Rollout Stages

1. **Stage 1 — Terraform**: SSM command fix + trigger bump + fmt/validate (T001–T003).
2. **Stage 2 — user-managed cluster validation**: CI apply with new image → Job recreated → `Completed` → rollout success (T004–T005).
