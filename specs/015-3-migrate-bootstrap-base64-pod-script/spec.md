# Spec: Migrate Bootstrap Base64 Pod Script

**Feature Branch**: `015-3-migrate-bootstrap-base64-pod-script` | **Date**: 2026-09-25 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: No new AWS resources, modules, or variables. Fix the 015-2 SSM bootstrap step in `terraform/environments/dev/main.tf` only.
- **Kubernetes / Cluster Scope**: No manifest changes (`backend-db-migrate.yaml`, `app-backend.yaml` untouched).
- **Target Services / Modules**: `null_resource.apply_app_backend` SSM command — bootstrap step only.
- **Security & CI/CD**: unchanged (SSM Run Command, SSM Parameter Store source of truth).

### 1.1 Root Cause (proven by cluster recreation run, instance i-06ffad2bd9a07d53d)
- `/bin/bash: line 42: MYSQL_ROOT_PASSWORD: unbound variable` — the text `$MYSQL_ROOT_PASSWORD` reached the **control-plane bash** (SSM script runs under `set -u`) as live text instead of staying inside the pod-side `sh -c '...'` single quotes. The pod-side quoting does not survive the Terraform → SSM JSON → control-plane shell layers.
- The same quote-boundary mangling explains both prior failures (015 `sh: GRANT: command not found`; 015-2 identical signature + Deployment step executing despite `&&`): broken quote boundaries split the chain into independently-executing pieces.

### 1.2 Terraform / HCL Resource Contracts
```hcl
# null_resource "apply_app_backend" — bootstrap step replaced (single &&-chain preserved):
#   triggers.migrate_rev = "015-3-base64-pod-script" (re-run)
#   OLD (015-2, mangled in transit):
#     printf '%s\n' '<B64_SQL>' | base64 -d | kubectl exec -i mysql-0 -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'
#   NEW (015-3): the ENTIRE pod-side script is base64-wrapped; the control plane
#   only ever handles quote-free base64 text:
#     echo '<B64_POD_SCRIPT>' | base64 -d | kubectl exec -i mysql-0 -n sdd-apps -- bash -s
#   where <B64_POD_SCRIPT> = base64encode(<<POD_SCRIPT) and POD_SCRIPT is:
#     mysql -uroot -p"$MYSQL_ROOT_PASSWORD" <<'SQL'
#     CREATE DATABASE IF NOT EXISTS sdd_backend;
#     GRANT ALL PRIVILEGES ON sdd_backend.* TO 'sdd_app'@'%';
#     FLUSH PRIVILEGES;
#     SQL
#   - Pod bash parses the decoded script: single quotes ('sdd_app'@'%') and the
#     heredoc delimiter are parsed by the shell that owns $MYSQL_ROOT_PASSWORD.
#   - <<'SQL' (quoted delimiter) = no expansion inside the heredoc; the password
#     reference expands only in the pod env, never as control-plane text.
#   - No printf, no \n escapes, no nested quote layers anywhere in the SSM text.
```
- **Gate contract**: unchanged from 015-2 — one `commands[]` entry, all steps `&&`-chained; conditional migrate block via `if ... fi`; failure anywhere blocks the Deployment apply.
- **HCL escaping contract**: the pod script is a single `base64encode()` call; the SSM command contains only its alphanumeric output. No `\"`, no `\\n`, no `$${...}` inside the wrapped region.

### 1.3 Data & Storage Contracts
- Unchanged from 015: `sdd_backend` pre-created idempotently; grants to `sdd_app`@`%`; migrate Job `backoffLimit: 0`; non-zero anywhere = fatal, rollout blocked.

### 1.4 Network & Security Contracts
- Unchanged: in-cluster `mysql-0:3306`; password expands only inside the mysql-0 pod (env from `mysql-secret`); no plaintext secrets in the SSM command or Terraform state beyond the existing pattern.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Terraform syntax & formatting validation passes (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: SSM command text contains no `$MYSQL_ROOT_PASSWORD`, no nested single quotes, no `\n` escapes (inspection of `main.tf` + `aws ssm get-command --query 'Commands[0].Parameters.commands'` shows quote-free base64 only)
- [ ] AC-003: DB bootstrap succeeds (`kubectl exec mysql-0 -n sdd-apps -- mysql -usdd_app -p"$MYSQL_PASSWORD" -e "USE sdd_backend; SHOW TABLES;"` exits 0)
- [ ] AC-004: Migrate Job reaches Complete with pod exitCode 0 (`kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s` exits 0)
- [ ] AC-005: Backend rollout succeeds only after Job completion (`kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` exits 0)
- [ ] AC-006: Gate enforcement: bootstrap failure blocks Deployment apply (single `&&` chain — verified by absence of independent steps in the executed command)

## 3. Assumptions & Technical Constraints
- **Image**: unchanged (SHA-tagged ECR `sdd-k8s-platform/backend`, arg `migrate`).
- **Network CIDRs / IAM / Security Boundaries**: unchanged.
- **External Prerequisites**: MySQL StatefulSet Ready on the recreated cluster; `mysql-secret` present; 015 manifests applied by their own null_resources.
- **Circular Dependency Prevention**: none introduced; `apply_app_backend` keeps `depends_on = [apply_mysql]`.
- **Testing Policy**: No test generation — validation via direct cluster CLI by the user.
