# Spec: Migrate Job Recreate On Apply

**Feature Branch**: `015-7-migrate-job-recreate-on-apply` | **Date**: 2026-09-26 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: No new AWS resources, modules, or variables. Fix the 015-6 SSM command in `terraform/environments/dev/main.tf`.
- **Root Cause (from SSM command invocation 1c946f7f)**: `The Job "backend-db-migrate" is invalid: spec.template: ... field is immutable`. Kubernetes never allows updating a Job's pod template. The previous run's Job still existed (within `ttlSecondsAfterFinished: 3600`), so re-applying the Job with the new SHA-tagged image hit the immutable-field error and the `&&` chain aborted before the Deployment step.
- **Fix**: delete the Job before applying it in the SSM chain — `kubectl delete job backend-db-migrate -n sdd-apps --ignore-not-found &&` prefix. The Job is one-shot and re-runnable by design; delete-and-recreate is the correct lifecycle and works at any deploy interval (not just after TTL expiry).

## 2. Contracts

### Terraform Contract (`main.tf`)
- In the `apply_app_backend` SSM command, prefix the migrate Job apply with `kubectl delete job backend-db-migrate -n sdd-apps --ignore-not-found &&` (inside the existing conditional migrate block, before the `kubectl apply` of the Job manifest).
- `migrate_rev` trigger bump: `"015-6-args-pull-secret"` → `"015-7-recreate-on-apply"` so the null_resource re-runs.
- No changes to the Job manifest (`backend-db-migrate.yaml`), substitution chain, or any other resource.

## 3. Acceptance Criteria (machine-verifiable)

- **AC-001**: `cd terraform/environments/dev && terraform fmt -check -recursive` → exit 0.
- **AC-002**: `cd terraform/environments/dev && terraform validate` (after `terraform init -backend=false`) → exit 0.
- **AC-003**: `grep -c 'delete job backend-db-migrate -n sdd-apps --ignore-not-found' terraform/environments/dev/main.tf` → 1.
- **AC-004**: `grep 'migrate_rev' terraform/environments/dev/main.tf` shows `015-7-recreate-on-apply`.
- **AC-005** (user-managed, cluster): after CI apply with a new backend image, the migrate Job is recreated (new controller-uid), reaches `Completed`, and the Deployment rollout succeeds — no `field is immutable` error in SSM stderr.

## 4. Rollout Stages

1. **Stage 1 (Terraform)**: SSM command fix + trigger bump + fmt/validate (T001–T003).
2. **Stage 2 (user-managed cluster validation)**: CI apply with new image → Job recreated → `Completed` → rollout success (T004–T005).
