# Spec: Migrate Job Entrypoint Arg Fix

**Feature Branch**: `015-5-migrate-job-entrypoint-arg-fix` | **Date**: 2026-09-25 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: No new AWS resources, modules, or variables. Fix the 015 migrate Job manifest in `terraform/environments/dev/manifests/backend-db-migrate.yaml`.
- **Root Cause (from cluster event)**: Job pod failed with `exec: "/app/backend": stat /app/backend: no such file or directory`. The manifest overrides the image entrypoint with `command: ["/app/backend", "migrate"]`, but the backend image binary is not at `/app/backend`.
- **Backend Contract**: the image ENTRYPOINT takes `migrate` as its first arg (default with no args = `serve`). The Job must NOT override the entrypoint path — pass only the arg.

## 2. Contracts

### Kubernetes Manifest Contract (`backend-db-migrate.yaml`)
- Replace `command: ["/app/backend", "migrate"]` with `command: ["migrate"]` — the image ENTRYPOINT runs with `migrate` as its first arg, per documented contract.
- All other Job fields unchanged: `backoffLimit: 0`, `activeDeadlineSeconds: 300`, `ttlSecondsAfterFinished: 3600`, `restartPolicy: Never`, env wiring to `mysql-secret` (`DB_USER`/`DB_PASSWORD`) + `DB_NAME=sdd_backend`, single-occurrence `%%MIGRATE_IMAGE%%`.

### Terraform Contract (`main.tf`)
- `migrate_rev` trigger bump: `"015-4-..."` → `"015-5-entrypoint-arg"` so `apply_app_backend` re-runs and re-applies the fixed Job manifest.

## 3. Acceptance Criteria (machine-verifiable)

- **AC-001**: `cd terraform/environments/dev && terraform fmt -check -recursive` → exit 0.
- **AC-002**: `cd terraform/environments/dev && terraform validate` (after `terraform init -backend=false`) → exit 0.
- **AC-003**: `grep -A1 'command:' terraform/environments/dev/manifests/backend-db-migrate.yaml` shows `command: ["migrate"]` (no `/app/backend` path anywhere in the file): `grep -c '/app/backend' terraform/environments/dev/manifests/backend-db-migrate.yaml` → 0.
- **AC-004**: `grep 'migrate_rev' terraform/environments/dev/main.tf` shows `015-5-entrypoint-arg`.
- **AC-005** (user-managed, cluster): after CI apply, migrate Job pod reaches `Completed` (exit 0), then Deployment rollout succeeds.

## 4. Rollout Stages

1. **Stage 1 (Terraform)**: manifest fix + trigger bump + fmt/validate (T001–T003).
2. **Stage 2 (user-managed cluster validation)**: CI apply → Job `Completed` → rollout success (T004–T005).
