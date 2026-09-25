# Execution Graph (DAG): Migrate Bootstrap Quote & Gate Fix

**Input**: Design documents from `/specs/015-2-migrate-bootstrap-quote-gate-fix/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

---

## Stage 1: Terraform Command Restructure

- [x] T001 [Stage 1: Terraform] Merge the 3 `commands[]` entries of `apply_app_backend` into a single `&&`-chained entry (pull-secret refresh && conditional migrate block && Deployment apply && rollout status) in `terraform/environments/dev/main.tf`
- [x] T002 [Stage 1: Terraform] Replace the nested-quote `-e` bootstrap with the stdin form: `printf '%s\n' "CREATE DATABASE IF NOT EXISTS sdd_backend; GRANT ALL PRIVILEGES ON sdd_backend.* TO 'sdd_app'@'%'; FLUSH PRIVILEGES;" | kubectl exec -i mysql-0 -n sdd-apps -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'` in `terraform/environments/dev/main.tf` (Depends on T001)
- [x] T003 [Stage 1: Terraform] Bump `migrate_rev` trigger to `"015-2-quote-gate-fix"` in `terraform/environments/dev/main.tf` (Depends on T002)
- [x] T004 [Stage 1: Terraform] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (plan/apply in CI only) (Depends on T003)

---

## Stage 2: Acceptance Validation (user-managed, direct cluster CLI)

- [ ] T005 [Stage 2: Validation] Verify AC-003: `kubectl exec mysql-0 -n sdd-apps -- mysql -usdd_app -p"$MYSQL_PASSWORD" -e "USE sdd_backend; SHOW TABLES;"` exits 0, no `command not found` in SSM stderr (Depends on T004)
- [ ] T006 [Stage 2: Validation] Verify AC-004/AC-005: Job Complete + `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` exits 0 (Depends on T005)
