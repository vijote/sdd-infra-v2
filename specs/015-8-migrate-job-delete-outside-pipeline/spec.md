# Spec: Migrate Job Delete Outside Pipeline

**Feature Branch**: `015-8-migrate-job-delete-outside-pipeline` | **Date**: 2026-09-26 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: No new AWS resources, modules, or variables. Fix the 015-7 SSM command in `terraform/environments/dev/main.tf`.
- **Root Cause (from SSM invocation)**: `error: no objects passed to apply`. The 015-7 delete was inserted *inside* the manifest pipeline (`printf | base64 -d | kubectl delete ... && kubectl apply -f -`), so the decoded manifest was piped into `kubectl delete` (which does not read stdin) and `kubectl apply -f -` received empty stdin. Stdout confirms: `job.batch "backend-db-migrate" deleted` ran, then apply failed.
- **Fix**: move the delete *before* the pipeline starts: `kubectl delete job backend-db-migrate -n sdd-apps --ignore-not-found && printf '%s\n' '<B64>' | base64 -d | kubectl apply -f - && kubectl wait --for=condition=complete ...`

## 2. Contracts

### Terraform Contract (`main.tf`)
- In the `apply_app_backend` SSM command's conditional migrate block, restructure to: delete job (standalone, before the pipe) `&&` pipeline (`printf | base64 -d | kubectl apply -f -`) `&&` `kubectl wait --for=condition=complete`.
- `migrate_rev` trigger bump: `"015-7-recreate-on-apply"` → `"015-8-delete-outside-pipeline"`.
- No changes to the Job manifest or substitution chain.

## 3. Acceptance Criteria (machine-verifiable)

- **AC-001**: `cd terraform/environments/dev && terraform fmt -check -recursive` → exit 0.
- **AC-002**: `cd terraform/environments/dev && terraform validate` (after `terraform init -backend=false`) → exit 0.
- **AC-003**: `grep -c 'delete job backend-db-migrate -n sdd-apps --ignore-not-found && printf' terraform/environments/dev/main.tf` → 1 (delete immediately followed by the pipeline start, not inside it).
- **AC-004**: `grep 'migrate_rev' terraform/environments/dev/main.tf` shows `015-8-delete-outside-pipeline`.
- **AC-005** (user-managed, cluster): after CI apply, SSM stderr has no `no objects passed to apply`; migrate Job recreated with new image, reaches `Completed`, Deployment rollout succeeds.

## 4. Rollout Stages

1. **Stage 1 (Terraform)**: SSM command restructure + trigger bump + fmt/validate (T001–T003).
2. **Stage 2 (user-managed cluster validation)**: CI apply → Job recreated → `Completed` → rollout success (T004–T005).
