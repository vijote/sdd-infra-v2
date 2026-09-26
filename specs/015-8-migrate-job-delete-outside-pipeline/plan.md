# Architecture Delta: Migrate Job Delete Outside Pipeline

**Branch**: `015-8-migrate-job-delete-outside-pipeline` | **Date**: 2026-09-26 | **Spec**: [specs/015-8-migrate-job-delete-outside-pipeline/spec.md](../spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/main.tf` | Modify | Move the Job delete before the manifest pipeline (`delete && printf | base64 -d | kubectl apply -f - && kubectl wait`); bump `migrate_rev` → `"015-8-delete-outside-pipeline"` |

No new files, variables, modules, or AWS resources. `backend-db-migrate.yaml` unchanged.

## 2. Architecture Notes

- **Pipeline stdin discipline**: `kubectl delete` does not read stdin; inserting it mid-pipeline starves `kubectl apply -f -` of the decoded manifest (`no objects passed to apply`). The delete must be a standalone command chained with `&&` before the pipe begins.
- `&&` gate semantics unchanged: delete failure, apply failure, or wait timeout all still block the Deployment apply.

## 3. Rollout Stages

1. **Stage 1 — Terraform**: SSM command restructure + trigger bump + fmt/validate (T001–T003).
2. **Stage 2 — user-managed cluster validation**: CI apply → Job recreated → `Completed` → rollout success (T004–T005).
