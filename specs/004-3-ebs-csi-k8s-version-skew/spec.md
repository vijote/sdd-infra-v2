# Spec: EBS CSI Driver K8s Version Skew Fix

**Feature Branch**: `004-3-ebs-csi-k8s-version-skew` | **Date**: 2026-09-12 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources)
- **Kubernetes / Cluster Scope**: EBS CSI driver re-pinned to a K8s 1.28-compatible release
- **Target Services / Modules**: EBS CSI driver `v1.28.0` (replaces `release-1.65` in 004-app-infrastructure)
- **Security & CI/CD**: all `kubectl` via SSM Run Command on the control plane (Flannel pattern, 003-3/003-11)

> **Root cause**: EBS CSI `release-1.65` targets K8s 1.33+ — its `CSIDriver` manifest sets `spec.nodeAllocatableUpdatePeriodSeconds`, a field absent from the K8s 1.28 API. The 1.28 API server rejects it (`strict decoding error: unknown field "spec.nodeAllocatableUpdatePeriodSeconds"`, exit 1). The `apply -k` created all other resources (SAs, RBAC, `ebs-csi-controller` Deployment, PDB, `ebs-csi-node` DaemonSet) then aborted on the CSIDriver; `set -e` (004-2) correctly surfaced the failure. The driver release must match the cluster's K8s minor version.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# terraform/environments/dev/main.tf — null_resource.apply_app_infrastructure:
# a) change the EBS CSI apply ref:
#    kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=v1.28.0"
# b) change the trigger so the provisioner re-runs:
#    ebs_csi_ref = "v1.28.0"   (was "release-1.65")
```

No other file changes. The 004-2 additions (`set -e`, `dnf install -y git`, `git_bootstrap` trigger) stay as-is — the git install is a harmless no-op on current AL2023 AMIs (git preinstalled) and defensive for older AMIs.

### 1.2 Kubernetes Manifest / Helm Values Contracts
- **EBS CSI driver** — `kubectl apply -k` gitops overlay `v1.28.0` (creates `ebs-csi-controller` Deployment + `ebs-csi-node` DaemonSet + `CSIDriver ebs.csi.aws.com` in `kube-system`). The v1.28.0 manifest is compatible with the K8s 1.28 API server.
- **Partial-state handling**: the failed `release-1.65` run left same-named resources (SAs, RBAC, Deployment, PDB, DaemonSet) without the CSIDriver. Re-applying `v1.28.0` updates them in place (idempotent `kubectl apply`) and creates the missing CSIDriver. No manual cleanup required.

### 1.3 Data & Storage Contracts
- N/A (`ebs-gp3` StorageClass already applied by 004; provisioner `ebs.csi.aws.com` unchanged).

### 1.4 Network & Security Contracts
- N/A (reuses the existing control-plane SSM channel; egress to `github.com` already exercised by the 004-2 run).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD. AC-001–AC-002 are static (existing `terraform-apply.yml` job). AC-003–AC-005 execute **on the control plane via SSM** — no public API endpoint, no kubeconfig in CI. Per P5/P6, AC-003–AC-005 are **user-managed verification**.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: EBS CSI `apply -k` succeeds against the v1.28.0 ref (exit 0, no CSIDriver decode error)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -k '\''github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=v1.28.0'\''"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-004: CSIDriver registered (`ebs.csi.aws.com` exists)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get csidriver ebs.csi.aws.com"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-005: EBS CSI controller + node plugin ready (rollout status by name — label-agnostic)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/ebs-csi-controller -n kube-system --timeout=300s && KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status daemonset/ebs-csi-node -n kube-system --timeout=300s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `004-app-infrastructure` (the `null_resource.apply_app_infrastructure` being fixed), `004-2-ebs-csi-git-missing` (git on control plane + `set -e` fail-fast), `003-12-flannel-cidr-mismatch` (EBS CSI pods need working pod networking to become Ready — AC-005 depends on Flannel being fixed).
- **Downstream Consumer**: `005-app-deployment` (MySQL StatefulSet PVC on `ebs-gp3` needs the EBS CSI driver running, including the CSIDriver object).
- **Version pairing rule**: the EBS CSI driver release must match the cluster's K8s minor version (driver v1.28.x ↔ K8s 1.28). If the cluster is ever upgraded (K8s 1.33+), the driver ref must be re-pinned in the same change.
- **Idempotency**: `kubectl apply -k` is re-runnable; the `null_resource` re-triggers on the changed `ebs_csi_ref` value.
- **Testing Policy**: No unit or E2E test generation — validation via direct AWS CLI + SSM checks in CI/CD.
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0.
