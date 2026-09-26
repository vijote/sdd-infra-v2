# Architecture Delta: Backend Deployment DB Env

**Branch**: `015-9-backend-deployment-db-env` | **Date**: 2026-09-26 | **Spec**: [specs/015-9-backend-deployment-db-env/spec.md](../spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/app-backend.yaml` | Modify | Add DB env block (`DB_HOST`/`DB_PORT`/`DB_USER`/`DB_PASSWORD`/`DB_NAME`) to the app-backend container |
| `terraform/environments/dev/main.tf` | Modify | `manifest_rev` trigger bump → `"015-9-db-env"` |

No new files, variables, modules, or AWS resources.

## 2. Architecture Notes

- The new backend code requires DB env at startup (both `migrate` and `serve`); the Deployment must carry the same env as the migrate Job (015-6). `DB_USER`/`DB_PASSWORD` come from the existing `mysql-secret` (SSM-sourced).
- The env block is static (no new placeholders), so the SSM substitution chain is untouched.

## 3. Rollout Stages

1. **Stage 1 — Terraform**: manifest env block + trigger bump + fmt/validate (T001–T003).
2. **Stage 2 — user-managed cluster validation**: CI apply → pods Ready → rollout 2/2 (T004–T005).
