# Execution Graph (DAG): MySQL StatefulSet (In-Cluster Database)

**Input**: Design documents from `/specs/005-mysql-statefulset/`
**Prerequisites**: `plan.md` (File Impact Matrix & Rollout Stages), `spec.md` (Contracts & ACs)
**Estimated Tasks**: 7 (3 implementation, 4 verification)
**Estimated Duration**: Short (2 files, reuses the established SSM apply pattern)
**Dependency Chain**: T001 → T002 → T003 → T004/T005/T006/T007

## Stage 1: Implementation

- [x] T001 [Stage 1: Manifest] Create `terraform/environments/dev/manifests/mysql.yaml` — 3 objects in `sdd-apps`: Secret `mysql-secret` (data: keys `MYSQL_ROOT_PASSWORD`/`MYSQL_PASSWORD` as `%%MYSQL_ROOT_PASSWORD_B64%%`/`%%MYSQL_PASSWORD_B64%%` tokens; `MYSQL_USER`/`MYSQL_DATABASE` as base64 constants `sdd_app`), StatefulSet `mysql` (image `mysql:8.0.36`, 1 replica, `volumeClaimTemplates` `mysql-data` on `ebs-gp3` 10Gi RWO, env from secret, readiness `mysqladmin ping -h 127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD"`, liveness `mysqladmin ping -h 127.0.0.1`, requests 256Mi/limits 512Mi), Service `mysql` (ClusterIP, port 3306)
- [x] T002 [Stage 1: Datasources] Add to `terraform/environments/dev/main.tf`: `data "aws_ssm_parameter" "mysql_root_password"` (`/sdd-k8s-platform/secrets/mysql-root-password`) and `data "aws_ssm_parameter" "mysql_password"` (`/sdd-k8s-platform/secrets/mysql-password`) (Depends on T001)
- [x] T003 [Stage 1: Apply] Add `null_resource.apply_mysql` to `terraform/environments/dev/main.tf` — `depends_on = [null_resource.apply_app_infrastructure]`, `triggers = { mysql_image = "8.0.36" }`, local-exec (bash interpreter): SSM-agent wait → 003-11 bootstrap-instance-id gate → `aws ssm send-command` with `commands=["set -e", "echo '<base64 manifest>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -"]` where the manifest is `base64encode(replace(replace(file("${path.module}/manifests/mysql.yaml"), "%%MYSQL_ROOT_PASSWORD_B64%%", base64encode(data.aws_ssm_parameter.mysql_root_password.value)), "%%MYSQL_PASSWORD_B64%%", base64encode(data.aws_ssm_parameter.mysql_password.value)))` → poll invocation to terminal (Depends on T002)

## Stage 2: Verification (CI / user-managed, per P5/P6)

- [ ] T004 [Stage 2: Static] Terraform syntax/format/plan valid — `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (AC-001, AC-002) (Depends on T003)
- [ ] T005 [Stage 2: SSM] Secret `mysql-secret` exists with all 4 keys (AC-003) (Depends on T003)
- [ ] T006 [Stage 2: SSM] PVC `mysql-data-mysql-0` phase `Bound` (AC-004) (Depends on T003)
- [ ] T007 [Stage 2: SSM] StatefulSet ready + authenticated query — `kubectl rollout status statefulset/mysql -n sdd-apps --timeout=600s` then `kubectl exec -n sdd-apps mysql-0 -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1"'` (AC-005, AC-006) (Depends on T003)

## Dependencies

```
T001 (manifests/mysql.yaml)
 └── T002 (main.tf: SSM datasources)
      └── T003 (main.tf: null_resource.apply_mysql)
           ├── T004 (static: fmt/validate/plan)
           ├── T005 (SSM: secret keys)
           ├── T006 (SSM: PVC Bound)
           └── T007 (SSM: rollout + SELECT 1)
```

## Parallelization

- T004, T005, T006, T007 are independent verification gates — can run in parallel in CI once T003 lands (T006/T007 are the slow ones: PVC provisioning + MySQL first init).

## Verification Task Mappings

| Task | AC | Channel |
|------|----|---------|
| T004 | AC-001, AC-002 | Static (existing `terraform-apply.yml`) |
| T005 | AC-003 | SSM Run Command on control plane |
| T006 | AC-004 | SSM Run Command on control plane |
| T007 | AC-005, AC-006 | SSM Run Command on control plane |
