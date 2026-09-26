# Spec: Migrate Job Args & Pull Secret

**Feature Branch**: `015-6-migrate-job-args-pull-secret` | **Date**: 2026-09-26 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: No new AWS resources, modules, or variables. Fix the 015 migrate Job manifest in `terraform/environments/dev/manifests/backend-db-migrate.yaml`.
- **Root Causes (proven via live cluster reproduction)**:
  1. `command: ["migrate"]` (015-5) **replaces** the image ENTRYPOINT — Kubernetes executes a binary literally named `migrate`, which does not exist → `StartError`. The backend contract (image ENTRYPOINT takes `migrate` as its first arg) requires `args`, not `command`.
  2. The Job never referenced `ecr-pull-secret` → anonymous ECR pull → `no basic auth credentials` (`ErrImagePull`). The kubelet ECR credential provider does not authenticate fresh pulls on these nodes; app-backend only worked because its image was already cached. The `sdd-apps` namespace already has `ecr-pull-secret` (011/014 wiring).
- **Live validation**: Job with `args: ["migrate"]` + `imagePullSecrets: [{name: ecr-pull-secret}]` reached `Completed` (exit 0) in the cluster.

## 2. Contracts

### Kubernetes Manifest Contract (`backend-db-migrate.yaml`)
- Replace `command: ["migrate"]` with `args: ["migrate"]` — image ENTRYPOINT runs with `migrate` as its first arg.
- Add under `spec.template.spec` (before `containers`): `imagePullSecrets: [{name: ecr-pull-secret}]`.
- All other Job fields unchanged: `backoffLimit: 0`, `activeDeadlineSeconds: 300`, `ttlSecondsAfterFinished: 3600`, `restartPolicy: Never`, env wiring to `mysql-secret` + `DB_NAME=sdd_backend`, single-occurrence `%%MIGRATE_IMAGE%%`.

### Terraform Contract (`main.tf`)
- `migrate_rev` trigger bump: `"015-5-entrypoint-arg"` → `"015-6-args-pull-secret"` so `apply_app_backend` re-runs and re-applies the fixed Job manifest.

## 3. Acceptance Criteria (machine-verifiable)

- **AC-001**: `cd terraform/environments/dev && terraform fmt -check -recursive` → exit 0.
- **AC-002**: `cd terraform/environments/dev && terraform validate` (after `terraform init -backend=false`) → exit 0.
- **AC-003**: `grep -c 'args: \["migrate"\]' terraform/environments/dev/manifests/backend-db-migrate.yaml` → 1; `grep -c 'command:' terraform/environments/dev/manifests/backend-db-migrate.yaml` → 0.
- **AC-004**: `grep -c 'name: ecr-pull-secret' terraform/environments/dev/manifests/backend-db-migrate.yaml` → 1.
- **AC-005**: `grep 'migrate_rev' terraform/environments/dev/main.tf` shows `015-6-args-pull-secret`.
- **AC-006** (user-managed, cluster): after CI apply, migrate Job reaches `Completed` (exit 0), then Deployment rollout succeeds.

## 4. Rollout Stages

1. **Stage 1 (Terraform)**: manifest fix (args + pull secret) + trigger bump + fmt/validate (T001–T003).
2. **Stage 2 (user-managed cluster validation)**: CI apply → Job `Completed` → rollout success (T004–T005).
