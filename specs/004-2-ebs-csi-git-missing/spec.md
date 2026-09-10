# Spec: EBS CSI Install — git Missing on Control Plane

**Feature Branch**: `004-2-ebs-csi-git-missing` | **Date**: 2026-09-10 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources)
- **Kubernetes / Cluster Scope**: EBS CSI driver (`ebs-csi-controller` Deployment, `ebs-csi-node` DaemonSet) / control-plane OS packages
- **Target Services / Modules**: EBS CSI driver `release-1.65` (004-app-infrastructure)
- **Security & CI/CD**: all `kubectl` via SSM Run Command on the control plane (Flannel pattern, 003-3/003-11)

> **Root cause**: `kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/...?ref=release-1.65"` requires `git` on the control plane to fetch the kustomization. The AL2023 control plane has no `git` → `error: no 'git' program on path` (exit 1). The 004 SSM command has no `set -e`, so the failure was swallowed and later commands (StorageClass, ingress) still ran — EBS CSI pods are absent while the rest of 004 succeeded.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# 1) terraform/modules/control-plane/bootstrap.sh — add git to the package install
#    (fresh clusters get git at first boot, alongside kubelet/kubeadm/kubectl):
#    dnf install -y git   (in the existing dnf install block)

# 2) terraform/environments/dev/main.tf — null_resource.apply_app_infrastructure:
#    a) add a first SSM command that installs git on the running control plane
#       (idempotent): "dnf install -y git"
#    b) add `set -e` semantics to the SSM command list so a failed step aborts the
#       rest (the 004 command currently swallows failures): prefix the command list
#       with "set -e" as the first entry.
#    c) add a trigger so the provisioner re-runs: git_bootstrap = "1"
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
- **EBS CSI driver** — `kubectl apply -k` gitops overlay `release-1.65` (creates `ebs-csi-controller` Deployment + `ebs-csi-node` DaemonSet in `kube-system`, provisioner `ebs.csi.aws.com`). No manifest change — the install command is unchanged; only the control plane gains `git`.

### 1.3 Data & Storage Contracts
- N/A (no storage contract change; `ebs-gp3` StorageClass already applied by 004).

### 1.4 Network & Security Contracts
- **Control-plane packages**: `git` installed via `dnf` (AL2023 default repos; egress to `repo.amazon.com` already allowed by the worker/control-plane SG egress-all rule).
- **No new security groups / IAM** (reuses the existing control-plane SSM channel).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD. AC-001–AC-002 are static (existing `terraform-apply.yml` job). AC-003–AC-005 execute **on the control plane via SSM** — no public API endpoint, no kubeconfig in CI. Per P5/P6, AC-003–AC-005 are **user-managed verification**.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: `git` is installed on the control plane
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["git --version"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'StandardOutputContent' --output text | grep -q '^git version'
  ```
- [ ] AC-004: EBS CSI controller + node plugin ready (rollout status by name — label-agnostic)
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
- [ ] AC-005: EBS CSI `apply -k` succeeds (exit 0, no git error)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -k '\''github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.65'\''"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `004-app-infrastructure` (the `null_resource.apply_app_infrastructure` being fixed), `003-12-flannel-cidr-mismatch` (EBS CSI pods need working pod networking to become Ready — AC-004 depends on Flannel being fixed).
- **Downstream Consumer**: `005-app-deployment` (MySQL StatefulSet PVC on `ebs-gp3` needs the EBS CSI driver running).
- **Fix mechanism**: install `git` on the control plane (bootstrap.sh for fresh clusters + SSM `dnf install -y git` for the running one) — most robust, future-proofs any kustomization install.
- **Failure visibility**: add `set -e` as the first SSM command so a failed step aborts the rest (the 004 command currently swallows failures).
- **Idempotency**: `dnf install -y git` and `kubectl apply -k` are re-runnable; the `null_resource` re-triggers on the new `git_bootstrap` trigger.
- **Testing Policy**: No unit or E2E test generation — validation via direct AWS CLI + SSM checks in CI/CD.
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0.
