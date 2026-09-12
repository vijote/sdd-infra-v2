# Spec: MySQL StatefulSet (In-Cluster Database)

**Feature Branch**: `005-mysql-statefulset` | **Date**: 2026-09-12 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources — EBS volume is dynamically provisioned by the EBS CSI driver via the `ebs-gp3` StorageClass)
- **Kubernetes / Cluster Scope**: MySQL 8.0.36 StatefulSet + PVC + Secret + ClusterIP Service in `sdd-apps`
- **Target Services / Modules**: `sdd-apps` namespace (004), `ebs-gp3` StorageClass (004), EBS CSI driver (004-3)
- **Security & CI/CD**: all `kubectl` via SSM Run Command on the control plane (Flannel pattern, 003-3/003-11); secrets via SSM Parameter Store datasources

### 1.1 Secrets Architecture (new reference pattern — applies to ALL cluster secrets)

- **Source of truth**: AWS SSM Parameter Store, `SecureString` type, under `/sdd-k8s-platform/secrets/`. Created **manually, one-time** (no Terraform resource, no GitHub secret):
  ```bash
  aws ssm put-parameter --name /sdd-k8s-platform/secrets/mysql-root-password --type SecureString --value '<root-pw>' --overwrite
  aws ssm put-parameter --name /sdd-k8s-platform/secrets/mysql-password --type SecureString --value '<app-pw>' --overwrite
  ```
  (Default KMS key `alias/aws/ssm` — no custom KMS key required.)
- **Terraform consumption**: `data "aws_ssm_parameter"` datasources (read-only; the `github-actions-assume-role` already has `ssm:GetParameter` via PowerUserAccess — no CloudFormation change).
- **GitHub footprint**: zero new secrets/vars for 005. GitHub keeps only non-secret vars (role ARNs, region, state bucket).
- **Injection into K8s**: the manifest carries `%%TOKEN%%` placeholders; Terraform replaces them with `base64encode(data.aws_ssm_parameter.X.value)` and the whole manifest is base64-encoded for the SSM command (003-6/004 pattern — zero JSON-escaping, zero special-char risk). The K8s Secret uses the `data:` field (base64 by definition).
- **Never in the SSM command**: passwords appear only as base64 inside the base64'd manifest; AC-006 reads the password from the pod's own env, not from the command line.

### 1.2 Terraform / HCL Resource Contracts

```hcl
# terraform/environments/dev/main.tf
data "aws_ssm_parameter" "mysql_root_password" { name = "/sdd-k8s-platform/secrets/mysql-root-password" }
data "aws_ssm_parameter" "mysql_password"      { name = "/sdd-k8s-platform/secrets/mysql-password" }

resource "null_resource" "apply_mysql" {
  depends_on = [null_resource.apply_app_infrastructure]
  triggers   = { mysql_image = "8.0.36" }
  # local-exec: SSM-agent wait → bootstrap-instance-id gate (003-11) → send-command:
  #   echo "<base64 manifest>" | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -
}
```

### 1.3 Kubernetes Manifest Contracts

`terraform/environments/dev/manifests/mysql.yaml` (3 objects, namespace `sdd-apps`):
- **Secret `mysql-secret`** — `data:` keys `MYSQL_ROOT_PASSWORD`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` (values base64-injected by Terraform; user `sdd_app`, database `sdd_app` are non-secret constants).
- **StatefulSet `mysql`** — image `mysql:8.0.36`, 1 replica, `volumeClaimTemplates` → PVC on `ebs-gp3` (10Gi, ReadWriteOnce), env from `mysql-secret`, readiness probe `sh -c 'mysqladmin ping -h 127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD"'`, liveness probe `mysqladmin ping -h 127.0.0.1`, resources requests 256Mi/limits 512Mi.
- **Service `mysql`** — ClusterIP, port 3306 (internal only; the future backend connects via `mysql.sdd-apps.svc.cluster.local`).

### 1.4 Data & Storage Contracts
- PVC `mysql-data-mysql-0` dynamically provisioned on `ebs-gp3` (gp3, 10Gi) by the EBS CSI driver — the first real end-to-end exercise of the 004 storage stack.
- Data survives pod restarts (StatefulSet stable identity); volume is deleted only on explicit PVC deletion.

### 1.5 Network & Security Contracts
- N/A (ClusterIP only; no ingress, no public exposure; reuses the control-plane SSM channel).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD. AC-001–AC-002 are static (existing `terraform-apply.yml` job). AC-003–AC-006 execute **on the control plane via SSM** — no public endpoint, no kubeconfig in CI. Per P5/P6, AC-003–AC-006 are **user-managed verification**.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Secret exists with all 4 keys
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get secret mysql-secret -n sdd-apps -o jsonpath='\''{.data.MYSQL_ROOT_PASSWORD}{.data.MYSQL_USER}{.data.MYSQL_PASSWORD}{.data.MYSQL_DATABASE}'\''"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-004: PVC bound (EBS volume provisioned by the CSI driver)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pvc mysql-data-mysql-0 -n sdd-apps -o jsonpath='\''{.status.phase}'\''"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 60); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-005: StatefulSet ready (pod Running, readiness probe passing)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status statefulset/mysql -n sdd-apps --timeout=600s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 60); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-006: MySQL accepts authenticated queries (password read from the pod's own env — never in the SSM command)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl exec -n sdd-apps mysql-0 -- sh -c '\''mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\" -e \"SELECT 1\"'\''"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `004-app-infrastructure` (`sdd-apps` ns + `ebs-gp3` SC), `004-3` (EBS CSI driver running), `003-12` (Flannel pod networking).
- **Downstream Consumer**: future backend spec (Node.js API) connects via `mysql.sdd-apps.svc.cluster.local:3306` using `sdd_app` / `mysql-password` param.
- **Manual prerequisite**: the two SecureString parameters must exist before `terraform apply` (datasources fail fast if absent). One-time, documented in §1.1.
- **Secrets pattern**: Parameter Store is the single source of truth for ALL cluster secrets; future specs reuse the `data "aws_ssm_parameter"` + `%%TOKEN%%` + base64 manifest pattern. AGENTS.md (local-only) should drop `MYSQL_ROOT_PASSWORD`/`MYSQL_PASSWORD` from the GitHub Secrets list.
- **Idempotency**: `kubectl apply` is re-runnable; the `null_resource` re-triggers only when `mysql_image` changes.
- **Testing Policy**: No unit or E2E test generation — validation via direct AWS CLI + SSM checks in CI/CD.
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0.
