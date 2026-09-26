# Architecture Delta: Migrate Job Args & Pull Secret

**Branch**: `015-6-migrate-job-args-pull-secret` | **Date**: 2026-09-26 | **Spec**: [specs/015-6-migrate-job-args-pull-secret/spec.md](../spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/backend-db-migrate.yaml` | Modify | `command: ["migrate"]` → `args: ["migrate"]`; add `imagePullSecrets: [{name: ecr-pull-secret}]` |
| `terraform/environments/dev/main.tf` | Modify | `migrate_rev` trigger bump → `"015-6-args-pull-secret"` |

No new files, variables, modules, or AWS resources.

## 2. Architecture Notes

- **`command` vs `args`**: in K8s, `command` overrides the image ENTRYPOINT; `args` appends to it. The backend contract (ENTRYPOINT consumes `migrate` as first arg) mandates `args`.
- **ECR auth**: kubelet ECR credential provider is not authenticating fresh pulls on these nodes; the existing `ecr-pull-secret` (011/014) is the working auth path — the Job must reference it via `imagePullSecrets`, same as any private-image workload in `sdd-apps`.
- `apply_app_backend` re-runs via the `migrate_rev` trigger bump; the SSM substitution chain is unchanged (`%%MIGRATE_IMAGE%%` placeholder untouched).

## 3. Rollout Stages

1. **Stage 1 — Terraform**: manifest fix + trigger bump + fmt/validate (T001–T003).
2. **Stage 2 — user-managed cluster validation**: CI apply → Job `Completed` → Deployment rollout success (T004–T005).
