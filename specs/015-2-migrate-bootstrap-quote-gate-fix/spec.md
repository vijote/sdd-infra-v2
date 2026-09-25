# Spec: Migrate Bootstrap Quote & Gate Fix

**Feature Branch**: `015-2-migrate-bootstrap-quote-gate-fix` | **Date**: 2026-09-25 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: No new AWS resources, modules, or variables. Fix the 015 SSM command in `terraform/environments/dev/main.tf` only.
- **Kubernetes / Cluster Scope**: No manifest changes (`backend-db-migrate.yaml`, `app-backend.yaml` untouched).
- **Target Services / Modules**: `null_resource.apply_app_backend` SSM command — bootstrap quoting + step gating.
- **Security & CI/CD**: unchanged (SSM Run Command, SSM Parameter Store source of truth).

### 1.1 Root Cause (from SSM invocation logs, instance i-0f90c4b85e2097f21)
- `sh: GRANT: command not found` / `sh: FLUSH: command not found` / exit 127: the inner single quotes in `TO 'sdd_app'@'%'` terminated the outer `sh -c '...'` quoting inside the pod, truncating the `-e` SQL string. `GRANT`/`FLUSH` leaked as separate shell commands.
- `deployment.apps/app-backend configured` appeared in stdout despite the bootstrap failure: SSM `commands[]` entries run independently, so the Deployment step executed even though the bootstrap step failed — the "Job complete before rollout" gate was not enforced.

### 1.2 Terraform / HCL Resource Contracts
```hcl
# null_resource "apply_app_backend" — SSM command restructured (single commands[] entry):
#   triggers.migrate_rev = "015-2-quote-gate-fix" (re-run)
#   One entry, && -chained, so any failure aborts the whole command:
#     refresh ecr-pull-secret
#     && if [ migrate_enabled = true ]:
#          printf '%s\n' "CREATE DATABASE IF NOT EXISTS sdd_backend; GRANT ALL PRIVILEGES ON sdd_backend.* TO 'sdd_app'@'%'; FLUSH PRIVILEGES;" \
#            | kubectl exec -i mysql-0 -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'
#          && kubectl apply -f backend-db-migrate.yaml (%%MIGRATE_IMAGE%% substituted)
#          && kubectl wait --for=condition=complete job/backend-db-migrate --timeout=300s
#     && kubectl apply -f app-backend.yaml (placeholders substituted)
#     && kubectl rollout status deployment/app-backend --timeout=180s
```
- **Quoting contract**: SQL reaches MySQL via **stdin** (`printf | kubectl exec -i`), never as nested `-e "..."` arguments. The SSM-side double-quoted string safely contains the SQL's single quotes; the pod-side `sh -c` contains only double quotes (`mysql -uroot -p"$MYSQL_ROOT_PASSWORD"`). Password expands inside the pod only.
- **Gate contract**: exactly one `commands[]` entry; every step joined with `&&`; the conditional migrate block uses `if ... then ... fi` inside the chain so baseline mode (tag empty) skips migrate but still applies the Deployment.

### 1.3 Data & Storage Contracts
- Unchanged from 015: `sdd_backend` pre-created idempotently; grants to `sdd_app`@`%`; migrate Job `backoffLimit: 0`, exit 0 = success; non-zero anywhere = fatal, rollout blocked.

### 1.4 Network & Security Contracts
- Unchanged: in-cluster `mysql-0:3306`; credentials from `mysql-secret`/SSM; no plaintext secrets in the SSM command (password referenced via pod env `$MYSQL_ROOT_PASSWORD`).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Terraform syntax & formatting validation passes (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: SSM command contains exactly one `commands[]` entry with all steps `&&`-chained (manual inspection of `main.tf` + `terraform validate`)
- [ ] AC-003: DB bootstrap succeeds with no `command not found` errors (`kubectl exec mysql-0 -n sdd-apps -- mysql -usdd_app -p"$MYSQL_PASSWORD" -e "USE sdd_backend; SHOW TABLES;"` exits 0)
- [ ] AC-004: Migrate Job reaches Complete with pod exitCode 0 (`kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s` exits 0)
- [ ] AC-005: Backend rollout succeeds only after Job completion (`kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` exits 0)
- [ ] AC-006: Gate enforcement: a forced bootstrap failure blocks the Deployment apply (verified by inspecting the single `&&` chain — no independent `commands[]` entries remain)

## 3. Assumptions & Technical Constraints
- **Image**: unchanged (SHA-tagged ECR `sdd-k8s-platform/backend`, arg `migrate`).
- **Network CIDRs / IAM / Security Boundaries**: unchanged.
- **External Prerequisites**: MySQL StatefulSet Ready; `mysql-secret` present; 015 manifests already applied (Job definition exists).
- **Circular Dependency Prevention**: none introduced; `apply_app_backend` keeps `depends_on = [apply_mysql]`.
- **Testing Policy**: No test generation — validation via direct cluster CLI by the user.
