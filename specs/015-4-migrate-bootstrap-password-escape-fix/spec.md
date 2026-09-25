# Spec: Migrate Bootstrap Password Escape Fix

**Feature Branch**: `015-4-migrate-bootstrap-password-escape-fix` | **Date**: 2026-09-25 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: No new AWS resources, modules, or variables. One-line HCL escape fix in `terraform/environments/dev/main.tf`.
- **Kubernetes / Cluster Scope**: No manifest changes.
- **Target Services / Modules**: `null_resource.apply_app_backend` SSM command — base64 payload escaping only.
- **Security & CI/CD**: unchanged.

### 1.1 Root Cause (proven by 015-3 run: `ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: YES)`)
- The 015-3 payload HCL used `-p\\\"$MYSQL_ROOT_PASSWORD\\\"`. HCL unescapes `\\\"` -> `\"` (backslash + quote), so the base64 payload contains `-p\"$MYSQL_ROOT_PASSWORD\"`.
- The pod's bash parses `\"` as an escaped literal quote char, so mysql receives the password wrapped in real `"` characters (`"<password>"`) -> wrong password -> ERROR 1045.
- PVC age (21m) matched the recreated cluster, ruling out a stale-volume cause; the payload escaping is the defect.

### 1.2 Terraform / HCL Resource Contracts
```hcl
# null_resource "apply_app_backend" — base64 payload escape fix (single &&-chain preserved):
#   triggers.migrate_rev = "015-4-password-escape-fix" (re-run)
#   OLD (015-3, wrong): base64encode("mysql -uroot -p\\\"$MYSQL_ROOT_PASSWORD\\\" <<'SQL'\n...")
#     -> payload contains -p\"$MYSQL_ROOT_PASSWORD\" -> pod bash: \" = literal quote char
#     -> mysql password = "<password>" (wrapped in quotes) -> Access denied
#   NEW (015-4): -p\"$MYSQL_ROOT_PASSWORD\" (single backslash in HCL)
#     -> HCL unescapes \" to " -> payload contains -p"$MYSQL_ROOT_PASSWORD"
#     -> pod bash: proper double-quote grouping -> mysql receives the raw password
#   Everything else (heredoc <<'SQL', SQL lines, kubectl exec -i bash -s, &&-chain) unchanged.
```
- **HCL escape contract**: inside the `base64encode("...")` string, a literal `"` in the payload is written `\"` (one backslash). `\\\"` is always wrong (yields backslash+quote in the payload).

### 1.3 Data & Storage Contracts
- Unchanged from 015-3: idempotent `sdd_backend` create + grants to `sdd_app`@`%`; migrate Job gate; non-zero anywhere = fatal.

### 1.4 Network & Security Contracts
- Unchanged: password expands only inside the mysql-0 pod env; no plaintext secrets in the SSM command.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Terraform syntax & formatting validation passes (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Decoded payload contains `-p"$MYSQL_ROOT_PASSWORD"` with no backslash before the quotes (local decode of the base64encode argument, or `aws ssm get-command --query 'Commands[0].Parameters.commands'` + base64 -d)
- [ ] AC-003: DB bootstrap succeeds (`kubectl exec mysql-0 -n sdd-apps -- mysql -usdd_app -p"$MYSQL_PASSWORD" -e "USE sdd_backend; SHOW TABLES;"` exits 0)
- [ ] AC-004: Migrate Job reaches Complete with pod exitCode 0 (`kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s` exits 0)
- [ ] AC-005: Backend rollout succeeds (`kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` exits 0)

## 3. Assumptions & Technical Constraints
- **Image**: unchanged. **Network CIDRs / IAM / Security Boundaries**: unchanged.
- **External Prerequisites**: MySQL StatefulSet Ready; `mysql-secret` present; 015 manifests applied.
- **Circular Dependency Prevention**: none introduced.
- **Testing Policy**: No test generation — validation via direct cluster CLI by the user.
