# Spec: Backend DB Migrate Job

**Feature Branch**: `015-backend-db-migrate-job` | **Date**: 2026-09-25 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: No new AWS resources; no new Terraform modules.
- **Kubernetes / Cluster Scope**: One-shot K8s Job `backend-db-migrate` in `sdd-apps` running the backend image with arg `migrate`, gated before the `app-backend` Deployment apply; DB/user bootstrap for `sdd_backend`.
- **Target Services / Modules**: `terraform/environments/dev` — `manifests/backend-db-migrate.yaml` (new), `manifests/app-backend.yaml` (probes), `main.tf` (`apply_app_backend` wiring).
- **Security & CI/CD**: Credentials from existing `mysql-secret` (SSM Parameter Store source of truth); applied via SSM Run Command on control plane (existing pattern).

### 1.1 Terraform / HCL Resource Contracts
```hcl
# No new variables. Existing inputs reused:
# var.backend_image_tag (string, default "") — selects ECR image vs nginx baseline
# var.mysql_root_password / var.mysql_password (sensitive, existing)

# locals (main.tf) — additions:
locals {
  # 015: migrate Job only applies when the real Go app is deployed (baseline
  # nginx:alpine has no migrate entrypoint arg and no DB).
  backend_migrate_enabled = var.backend_image_tag != ""
}

# null_resource "apply_app_backend" — modified:
#   triggers.migrate_rev = "015-initial" (re-run on Job manifest change)
#   SSM command sequence (single send-command, ordered):
#     1. (existing) refresh ecr-pull-secret
#     2. NEW: if backend_migrate_enabled: apply backend-db-migrate.yaml
#        (placeholders substituted) + kubectl wait --for=condition=complete
#        job/backend-db-migrate -n sdd-apps --timeout=300s
#        (non-zero exit of any step aborts the SSM command -> apply fails)
#     3. (existing) apply app-backend.yaml + rollout status
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# terraform/environments/dev/manifests/backend-db-migrate.yaml (new)
apiVersion: batch/v1
kind: Job
metadata:
  name: backend-db-migrate
  namespace: sdd-apps
  labels:
    app: backend-db-migrate
spec:
  backoffLimit: 0            # non-zero exit = fatal, no retries
  ttlSecondsAfterFinished: 3600
  activeDeadlineSeconds: 300
  template:
    metadata:
      labels:
        app: backend-db-migrate
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: %%MIGRATE_IMAGE%%          # same SHA-tagged ECR image as the app
          imagePullPolicy: IfNotPresent
          command: ["/app/backend", "migrate"]  # entrypoint arg; default (no args) = serve
          env:
            - name: DB_HOST
              value: mysql.sdd-apps.svc.cluster.local
            - name: DB_PORT
              value: "3306"
            - name: DB_USER
              valueFrom: { secretKeyRef: { name: mysql-secret, key: MYSQL_USER } }
            - name: DB_PASSWORD
              valueFrom: { secretKeyRef: { name: mysql-secret, key: MYSQL_PASSWORD } }
            - name: DB_NAME
              value: sdd_backend
```
- `%%MIGRATE_IMAGE%%` substituted with `local.backend_image` (single occurrence, 014 gotcha).
- `app-backend.yaml` probe change (015): readiness probe path `%%BACKEND_PROBE_PATH%%` -> `/readyz` when ECR tag set (DB ping, 503 removes pod from endpoints); liveness stays `/healthz` (no DB). New single-occurrence placeholders `%%BACKEND_LIVENESS_PATH%%` / `%%BACKEND_READINESS_PATH%%` replace `%%BACKEND_PROBE_PATH%%`; nginx baseline keeps `/` for both.

### 1.3 Data & Storage Contracts
- **Database / Schema Migrations**: `migrate` subcommand migrates schema inside `DB_NAME` (`sdd_backend`) but does NOT create the database. Bootstrap step (idempotent, runs in the same SSM command before the Job): `kubectl exec mysql-0 -- mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS sdd_backend; GRANT ALL PRIVILEGES ON sdd_backend.* TO 'sdd_app'@'%'; FLUSH PRIVILEGES;"` — root password read from `mysql-secret` inside the MySQL pod env.
- **Exit codes**: Job pod exit 0 = success (incl. already-current schema); any non-zero -> Job fails -> `kubectl wait --for=condition=complete` times out -> SSM command exits non-zero -> `apply_app_backend` fails -> rollout blocked.
- **Ordering**: MySQL reachable (StatefulSet Ready, `apply_mysql` dependency) -> DB/user bootstrap -> migrate Job complete -> `app-backend` Deployment apply/rollout. `serve` pings DB on connect, so ordering is enforced end-to-end.

### 1.4 Network & Security Contracts
- **Credentials**: `DB_PASSWORD` injected from `mysql-secret` (SSM SecureString source of truth); no plaintext in manifests or Terraform state beyond existing pattern. Explicit non-root `DB_USER` (`sdd_app`), never root.
- **Network**: In-cluster only — Job -> `mysql.sdd-apps.svc.cluster.local:3306` (ClusterIP, existing SG rules).
- **Concurrency**: Single-run Job (not init container) = strict serialization; no concurrent migrate during rolling updates. GET_LOCK advisory lock explicitly deferred.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Terraform syntax & formatting validation passes (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected delta without errors (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Migrate Job reaches Complete (`kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s` exits 0)
- [ ] AC-004: Migrate Job pod exit code is 0 (`kubectl get pod -n sdd-apps -l job-name=backend-db-migrate -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.exitCode}'` returns `0`)
- [ ] AC-005: Database and grants exist (`kubectl exec mysql-0 -n sdd-apps -- mysql -usdd_app -p"$MYSQL_PASSWORD" -e "USE sdd_backend; SHOW TABLES;"` exits 0)
- [ ] AC-006: Backend rollout succeeds after Job completion (`kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` exits 0)
- [ ] AC-007: Readiness probe reflects DB ping (`kubectl get deployment app-backend -n sdd-apps -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}'` returns `/readyz` when ECR tag set)

## 3. Assumptions & Technical Constraints
- **Image**: `sdd-k8s-platform/backend` ECR repo, SHA-tagged (same image as the app); entrypoint arg `migrate`, default `serve`.
- **Network CIDRs**: unchanged (VPC 10.0.0.0/16, Pod 192.168.0.0/16, Service 10.96.0.0/12).
- **IAM / Security Boundaries**: unchanged; SSM Run Command on control plane (existing node role SSM permissions).
- **External Prerequisites**: MySQL StatefulSet Ready (`apply_mysql`); `mysql-secret` present in `sdd-apps`.
- **Baseline mode**: when `backend_image_tag == ""`, migrate Job and DB bootstrap are skipped entirely (nginx:alpine has no migrate arg and no DB dependency).
- **Circular Dependency Prevention**: none introduced; `apply_app_backend` keeps `depends_on = [apply_mysql]`; no downstream CCM/ingress dependents added.
- **Testing Policy**: No unit or E2E test generation — validation performed directly against AWS infrastructure using CLI tools.
