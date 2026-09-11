# Architecture Delta: EBS CSI Install — git Missing on Control Plane

**Branch**: `004-2-ebs-csi-git-missing` | **Date**: 2026-09-10 | **Status**: Draft

## 1. File Impact Matrix

| File | Op | Purpose / Exports |
|------|----|-------------------|
| `terraform/modules/control-plane/bootstrap.sh` | Modify | Add `dnf install -y git` (dedicated line after the k8s install block) so **fresh** control planes have `git` at first boot — future-proofs any `kubectl apply -k` kustomization install. |
| `terraform/environments/dev/main.tf` | Modify | `null_resource.apply_app_infrastructure`: (a) prepend `set -e` as the first SSM command entry (fail-fast — the 004 command currently swallows failures), (b) add `dnf install -y git` as the next entry (installs git on the **running** control plane, idempotent), (c) add trigger `git_bootstrap = "1"` so the provisioner re-runs on the next apply. |

No new AWS resources. No new module. No manifest change (the EBS CSI `apply -k` command is unchanged — only the control plane gains `git`).

## 2. Architecture Delta

### 2.1 Root cause
`kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/...?ref=release-1.65"` requires `git` on the control plane to fetch the kustomization. The AL2023 control plane has no `git` → `error: no 'git' program on path` (exit 1). The 004 SSM command had no `set -e`, so the failure was swallowed and the later commands (StorageClass, ingress) still ran — EBS CSI pods are absent while the rest of 004 succeeded.

### 2.2 Fix mechanism (two-pronged)
- **Fresh clusters**: `bootstrap.sh` installs `git` at first boot (alongside kubelet/kubeadm/kubectl). Any future control plane replacement is git-ready.
- **Running cluster**: the `apply_app_infrastructure` SSM command installs `git` on the current control plane before the EBS CSI `apply -k` runs. No need to replace the control plane again.

### 2.3 Failure visibility
`set -e` as the first SSM command entry makes the concatenated script abort on the first failing step (the 004 command previously reported `Success` even though the EBS CSI step failed). This matches the 003-3 Flannel fail-fast pattern.

### 2.4 Re-trigger
Adding `git_bootstrap = "1"` to `triggers` changes the trigger hash, so the next `terraform apply` re-runs the provisioner → installs git → re-applies EBS CSI (idempotent `kubectl apply -k`).

## 3. Provisioning & Rollout Stages

1. **Terraform apply** — `bootstrap.sh` change is inert for the existing cluster (user-data runs once at first boot); the `apply_app_infrastructure` trigger change re-runs the provisioner.
2. **SSM: install git** — `set -e` + `dnf install -y git` on the running control plane (idempotent).
3. **SSM: re-apply app infra** — namespace → EBS CSI `apply -k` (now succeeds with git present) → StorageClass → ingress, all fail-fast under `set -e`.
4. **Pod readiness** — EBS CSI controller Deployment + node DaemonSet become Ready (requires working Flannel pod networking from 003-12).

## 4. Verification Gates (CI / user-managed, per P5/P6)

- **AC-001/AC-002** (static, existing `terraform-apply.yml`): `terraform fmt -check -recursive && terraform validate`; `terraform plan -detailed-exitcode`.
- **AC-003** (SSM): `git --version` on the control plane → `^git version`.
- **AC-004** (SSM): `kubectl rollout status deployment/ebs-csi-controller` + `daemonset/ebs-csi-node` (label-agnostic, `-n kube-system`, `--timeout=300s`).
- **AC-005** (SSM): `kubectl apply -k ...release-1.65` exits `Success` (no git error).

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `dnf install -y git` needs egress to `repo.amazon.com` | Already allowed by the control-plane SG egress-all rule (same repo used for containerd/k8s). |
| EBS CSI pods stay `ContainerCreating` if Flannel is broken | 003-12 (CIDR fix) is a prerequisite — AC-004 depends on working pod networking. |
| `set -e` aborts before ingress if an earlier step fails | Intended — surfaces the real failure instead of swallowing it; re-run is idempotent. |
| Provisioner re-runs on every apply | Trigger is a stable literal (`"1"`); re-runs only when the value changes (this apply) or a pinned ref changes. |
