# Architecture Delta: Migrate Bootstrap Base64 Pod Script

**Branch**: `015-3-migrate-bootstrap-base64-pod-script` | **Date**: 2026-09-25 | **Spec**: [specs/015-3-migrate-bootstrap-base64-pod-script/spec.md](../spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/main.tf` | Modify | Replace 015-2 bootstrap step with base64-wrapped pod script (`echo '<B64>' | base64 -d | kubectl exec -i mysql-0 -- bash -s`); bump `migrate_rev` trigger to `015-3-base64-pod-script` |

No other files change. No new variables, modules, manifests, or AWS resources.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: unchanged.
- **Application Workloads**: `apply_mysql` -> (single SSM &&-chain): pull-secret refresh -> conditional [base64 pod-script bootstrap -> migrate Job apply -> wait complete] -> Deployment apply -> rollout status.
- **Quoting boundary (the fix)**: control-plane shell sees only base64 text; SQL single quotes + `$MYSQL_ROOT_PASSWORD` live inside the base64 payload, parsed by the pod's bash via `kubectl exec -i ... -- bash -s`.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` in CI — trigger bump re-runs `apply_app_backend`.
2. **Stage 2 - SSM Command (single entry, &&-chained)**:
   a. Refresh `ecr-pull-secret` (existing).
   b. If `backend_migrate_enabled`: `echo '<B64_POD_SCRIPT>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl exec -i mysql-0 -n sdd-apps -- bash -s` where the decoded script is:
      ```
      mysql -uroot -p"$MYSQL_ROOT_PASSWORD" <<'SQL'
      CREATE DATABASE IF NOT EXISTS sdd_backend;
      GRANT ALL PRIVILEGES ON sdd_backend.* TO 'sdd_app'@'%';
      FLUSH PRIVILEGES;
      SQL
      ```
   c. Apply `backend-db-migrate.yaml` + `kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s`.
   d. Apply `app-backend.yaml` + `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s`.
3. **Stage 3 - Baseline mode**: `backend_image_tag == ""` -> steps b/c skipped via `if ... fi`; Deployment still applied.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate`
- **Command Text**: `aws ssm get-command --command-id <ID> --query 'Commands[0].Parameters.commands'` — quote-free base64 only, no `$MYSQL_ROOT_PASSWORD` as live text
- **Bootstrap Success**: `USE sdd_backend; SHOW TABLES;` as `sdd_app` exits 0
- **Job Gate**: `kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s`
- **Rollout**: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s`
