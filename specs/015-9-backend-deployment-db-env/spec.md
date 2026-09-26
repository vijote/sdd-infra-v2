# Spec: Backend Deployment DB Env

**Feature Branch**: `015-9-backend-deployment-db-env` | **Date**: 2026-09-26 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: No new AWS resources, modules, or variables. Fix the app-backend Deployment manifest in `terraform/environments/dev/manifests/app-backend.yaml`.
- **Root Cause (from pod logs)**: `failed to connect to database: database open: dial tcp [::1]:3306: connect: connection refused` — the new backend code requires DB env (`DB_HOST` required per backend contract); the Deployment container has **no DB env at all**, so the code falls back to a localhost default and crash-loops. The migrate Job (015-6) has the correct env; the Deployment never did (old nginx baseline didn't connect to a DB).
- **Fix**: add the identical DB env block to the app-backend Deployment container.

## 2. Contracts

### Kubernetes Manifest Contract (`app-backend.yaml`)
- Add to the `app-backend` container (after `ports`, before `readinessProbe`):
  - `DB_HOST` = `mysql.sdd-apps.svc.cluster.local`
  - `DB_PORT` = `"3306"`
  - `DB_USER` = secretKeyRef `mysql-secret` / `MYSQL_USER`
  - `DB_PASSWORD` = secretKeyRef `mysql-secret` / `MYSQL_PASSWORD`
  - `DB_NAME` = `sdd_backend`
- All existing placeholders unchanged (each appears exactly once — 014 gotcha).

### Terraform Contract (`main.tf`)
- `manifest_rev` trigger bump: `"012-5-probe-path"` → `"015-9-db-env"` so `apply_app_backend` re-runs and re-applies the Deployment.

## 3. Acceptance Criteria (machine-verifiable)

- **AC-001**: `cd terraform/environments/dev && terraform fmt -check -recursive` → exit 0.
- **AC-002**: `cd terraform/environments/dev && terraform validate` (after `terraform init -backend=false`) → exit 0.
- **AC-003**: `grep -c 'name: DB_HOST' terraform/environments/dev/manifests/app-backend.yaml` → 1; `grep -c 'name: DB_PASSWORD' terraform/environments/dev/manifests/app-backend.yaml` → 1.
- **AC-004**: `grep 'manifest_rev' terraform/environments/dev/main.tf` shows `015-9-db-env`.
- **AC-005** (user-managed, cluster): after CI apply, app-backend pods become Ready (no `dial tcp [::1]` in logs), rollout completes 2/2.

## 4. Rollout Stages

1. **Stage 1 (Terraform)**: manifest env block + trigger bump + fmt/validate (T001–T003).
2. **Stage 2 (user-managed cluster validation)**: CI apply → pods Ready → rollout 2/2 (T004–T005).
