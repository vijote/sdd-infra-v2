# Architecture Delta: Migrate Job Entrypoint Arg Fix

**Branch**: `015-5-migrate-job-entrypoint-arg-fix` | **Date**: 2026-09-25 | **Spec**: [specs/015-5-migrate-job-entrypoint-arg-fix/spec.md](../spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/backend-db-migrate.yaml` | Modify | `command: ["/app/backend", "migrate"]` → `command: ["migrate"]` (entrypoint arg only) |
| `terraform/environments/dev/main.tf` | Modify | `migrate_rev` trigger bump → `"015-5-entrypoint-arg"` |

No new files, variables, modules, or AWS resources.

## 2. Architecture Notes

- The backend image ENTRYPOINT consumes `migrate` as its first arg (documented backend contract). Overriding `command` with a binary path assumed a layout (`/app/backend`) that does not exist in the image — the Job must pass only the arg and let the image entrypoint resolve the binary.
- `apply_app_backend` re-runs via the `migrate_rev` trigger bump; the Job manifest is re-applied through the existing SSM substitution chain (no chain changes needed — `%%MIGRATE_IMAGE%%` placeholder unchanged).

## 3. Rollout Stages

1. **Stage 1 — Terraform**: manifest fix + trigger bump + fmt/validate (T001–T003).
2. **Stage 2 — user-managed cluster validation**: CI apply → Job `Completed` → Deployment rollout success (T004–T005).
