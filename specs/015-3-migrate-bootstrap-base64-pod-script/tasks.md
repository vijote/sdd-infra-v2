# Execution Graph (DAG): Migrate Bootstrap Base64 Pod Script

**Input**: Design documents from `/specs/015-3-migrate-bootstrap-base64-pod-script/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

---

## Stage 1: Terraform Bootstrap Rewrite

- [x] T001 [Stage 1: Terraform] Replace the 015-2 bootstrap step with the base64-wrapped pod script: `echo '${base64encode("mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\" <<'SQL'\nCREATE DATABASE IF NOT EXISTS sdd_backend;\nGRANT ALL PRIVILEGES ON sdd_backend.* TO 'sdd_app'@'%';\nFLUSH PRIVILEGES;\nSQL")}' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl exec -i mysql-0 -n sdd-apps -- bash -s` in `terraform/environments/dev/main.tf`
- [x] T002 [Stage 1: Terraform] Bump `migrate_rev` trigger to `"015-3-base64-pod-script"` in `terraform/environments/dev/main.tf` (Depends on T001)
- [x] T003 [Stage 1: Terraform] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (plan/apply in CI only) (Depends on T002)

---

## Stage 2: Acceptance Validation (user-managed, direct cluster CLI)

- [ ] T004 [Stage 2: Validation] Verify AC-002: `aws ssm get-command --command-id <ID> --query 'Commands[0].Parameters.commands'` shows quote-free base64 only (no live `$MYSQL_ROOT_PASSWORD`, no nested quotes) (Depends on T003)
- [ ] T005 [Stage 2: Validation] Verify AC-003/AC-004/AC-005: bootstrap exits 0, Job Complete, `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` exits 0 (Depends on T004)
