# Architecture Delta: Backend DB Migrate Job

**Branch**: `015-backend-db-migrate-job` | **Date**: 2026-09-25 | **Spec**: [specs/015-backend-db-migrate-job/spec.md](../spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/backend-db-migrate.yaml` | Create | batch/v1 Job `backend-db-migrate` — one-shot migrate run (`%%MIGRATE_IMAGE%%` single-occurrence placeholder, env from `mysql-secret`) |
| `terraform/environments/dev/manifests/app-backend.yaml` | Modify | Split `%%BACKEND_PROBE_PATH%%` -> `%%BACKEND_LIVENESS_PATH%%` + `%%BACKEND_READINESS_PATH%%` (Go app: `/healthz` + `/readyz`; baseline: `/` + `/`) |
| `terraform/environments/dev/main.tf` | Modify | locals: `backend_liveness_path`, `backend_readiness_path`, `backend_migrate_enabled`; `apply_app_backend`: triggers (`migrate_rev`), SSM command adds DB/user bootstrap + Job apply + `kubectl wait --for=condition=complete` before Deployment apply |

No new Terraform variables, modules, or AWS resources. No changes to `variables.tf`, `outputs.tf`, or any other manifest.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: unchanged — VPC, EC2, SGs, IAM, SSM Parameter Store (secrets source of truth).
- **Cluster Control Plane & Core Addons**: unchanged — kubeadm 1.28.0, Flannel, EBS CSI, CCM.
- **Platform Services**: unchanged — cert-manager, ingress-nginx, Cloudflare DNS.
- **Application Workloads**: MySQL StatefulSet (`mysql-0`, Ready via `apply_mysql`) -> **NEW** DB/user bootstrap (`CREATE DATABASE IF NOT EXISTS sdd_backend` + grants to `sdd_app`) -> **NEW** migrate Job (Complete gate) -> `app-backend` Deployment (2 replicas, probes `/healthz` liveness / `/readyz` readiness).
- **Shared Dependencies**: `mysql-secret` in `sdd-apps` (MYSQL_USER/MYSQL_PASSWORD keys); `ecr-pull-secret` for ECR image pull; `local.backend_image` (SHA-tagged ECR image shared by Job and Deployment); SSM Run Command pattern on control plane.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` — locals + `apply_app_backend` trigger change re-runs the null_resource (existing SSM pattern; no new resources).
2. **Stage 2 - SSM Command (control plane, single send-command, ordered)**:
   a. Refresh `ecr-pull-secret` (existing, 12h ECR token).
   b. DB/user bootstrap: `kubectl exec mysql-0 -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS sdd_backend; GRANT ALL PRIVILEGES ON sdd_backend.* TO '\''sdd_app'\''@'\''%'\''; FLUSH PRIVILEGES;"'` (idempotent).
   c. Apply `backend-db-migrate.yaml` (placeholders substituted) + `kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s` — non-zero exit aborts (backoffLimit 0, no retries).
   d. Apply `app-backend.yaml` + `kubectl rollout status deployment/app-backend --timeout=180s` (existing).
3. **Stage 3 - Baseline mode**: `backend_image_tag == ""` -> steps b/c skipped (`backend_migrate_enabled` false), Job manifest not applied, probes stay `/`.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode`
- **Job Completion**: `kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s`
- **Job Exit Code**: `kubectl get pod -n sdd-apps -l job-name=backend-db-migrate -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.exitCode}'` = `0`
- **DB Verification**: `kubectl exec mysql-0 -n sdd-apps -- mysql -usdd_app -p"$MYSQL_PASSWORD" -e "USE sdd_backend; SHOW TABLES;"`
- **Service Rollout**: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s`
- **Probe Contract**: `kubectl get deployment app-backend -n sdd-apps -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}'` = `/readyz` (ECR mode)
