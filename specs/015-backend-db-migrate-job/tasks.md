# Execution Graph (DAG): Backend DB Migrate Job

**Input**: Design documents from `/specs/015-backend-db-migrate-job/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`

---

## Stage 1: Terraform & Manifest Foundations

- [x] T001 [Stage 1: Terraform] Create batch/v1 Job `backend-db-migrate` manifest (backoffLimit 0, ttlSecondsAfterFinished 3600, activeDeadlineSeconds 300, restartPolicy Never, container arg `migrate`, env DB_HOST=mysql.sdd-apps.svc.cluster.local / DB_PORT=3306 / DB_USER+DB_PASSWORD from mysql-secret / DB_NAME=sdd_backend, single-occurrence `%%MIGRATE_IMAGE%%` placeholder) in `terraform/environments/dev/manifests/backend-db-migrate.yaml`
- [x] T002 [Stage 1: Terraform] Replace `%%BACKEND_PROBE_PATH%%` with `%%BACKEND_LIVENESS_PATH%%` (livenessProbe) and `%%BACKEND_READINESS_PATH%%` (readinessProbe), each single-occurrence, in `terraform/environments/dev/manifests/app-backend.yaml` (Depends on T001)
- [x] T003 [Stage 1: Terraform] Add locals `backend_liveness_path` (tag=="" ? "/" : "/healthz"), `backend_readiness_path` (tag=="" ? "/" : "/readyz"), `backend_migrate_enabled` (tag != "") in `terraform/environments/dev/main.tf` (Depends on T002)
- [x] T004 [Stage 1: Terraform] Extend `apply_app_backend` triggers with `migrate_rev = "015-initial"` and `probe_rev = "015-readyz"` in `terraform/environments/dev/main.tf` (Depends on T003)
- [x] T005 [Stage 1: Terraform] Extend `apply_app_backend` SSM command: substitute new placeholders (`%%MIGRATE_IMAGE%%` <- local.backend_image, `%%BACKEND_LIVENESS_PATH%%`, `%%BACKEND_READINESS_PATH%%`) in the base64 replace chain in `terraform/environments/dev/main.tf` (Depends on T004)
- [x] T006 [Stage 1: Terraform] Insert ordered SSM steps between pull-secret refresh and Deployment apply: (a) conditional DB/user bootstrap via `kubectl exec mysql-0 -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS sdd_backend; GRANT ALL PRIVILEGES ON sdd_backend.* TO '\''sdd_app'\''@'\''%'\''; FLUSH PRIVILEGES;"'` guarded by `backend_migrate_enabled`; (b) conditional `kubectl apply -f` of backend-db-migrate.yaml + `kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s` in `terraform/environments/dev/main.tf` (Depends on T005)
- [x] T007 [Stage 1: Terraform] Run `terraform fmt -check -recursive && terraform validate` in `terraform/environments/dev` (plan/apply run in CI only) (Depends on T006)

---

## Stage 2: Acceptance Validation (user-managed, direct cluster CLI)

- [ ] T008 [Stage 2: Validation] Verify AC-003/AC-004: `kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s` and Job pod exitCode = 0 (Depends on T007)
- [ ] T009 [Stage 2: Validation] Verify AC-005: `kubectl exec mysql-0 -n sdd-apps -- mysql -usdd_app -p"$MYSQL_PASSWORD" -e "USE sdd_backend; SHOW TABLES;"` (Depends on T008)
- [ ] T010 [Stage 2: Validation] Verify AC-006/AC-007: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` and readinessProbe path = `/readyz` (Depends on T009)
