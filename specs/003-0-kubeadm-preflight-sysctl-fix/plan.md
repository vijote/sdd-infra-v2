# Architecture Delta: Kubeadm Preflight Sysctl Fix

**Branch**: `003-0-kubeadm-preflight-sysctl-fix` | **Date**: 2026-09-05 | **Spec**: specs/003-0-kubeadm-preflight-sysctl-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/modules/control-plane/bootstrap.sh` | Modify | (A) Insert `modprobe br_netfilter` + `/etc/sysctl.d/99-kubernetes.conf` (3 sysctls) + `sysctl --system` before `kubeadm init`; (B) remove the KubeletConfiguration document (lines 70–73) from the kubeadm config heredoc |

**No other files change.** Terraform resources, dev environment, workflows, and all other modules are untouched — this is a bootstrap-script-only correction.

## 2. Architectural Boundaries & Dependency Flow

- **Boundary**: The fix lives in the node bootstrap layer (003-2's `bootstrap.sh`) — no Terraform resource change, no CloudFormation, no IAM change
- **Root cause (fatal)**: `kubeadm init` preflight requires `br_netfilter` loaded (else `/proc/sys/net/bridge/bridge-nf-call-iptables` is absent) and `net.ipv4.ip_forward = 1`; AL2023 ships with neither configured, so preflight aborts before any cluster work
- **Root cause (warning)**: the KubeletConfiguration document in the kubeadm config is ignored by kubeadm (wrong GVK group) and redundant (containerd already `SystemdCgroup = true`)
- **Fix flow**: `modprobe br_netfilter` → sysctl file written → `sysctl --system` applies → preflight passes → `kubeadm init` succeeds → join command published to SSM
- **Consumers**:
  - 003-2 control plane user-data → `kubeadm init` (now passes preflight) → `ssm put-parameter`
  - 003-3 workers (future) → read the join command from SSM
- **Instance replacement**: `user_data` is embedded in the instance; changing `bootstrap.sh` changes its hash, so Terraform **replaces** the control plane instance (destroy + re-launch) and the corrected bootstrap re-runs at first boot

## 3. Provisioning & Rollout Stages

- **Stage 1 — Script edit (agent)**: Apply Fix A (br_netfilter + sysctls) and Fix B (remove KubeletConfiguration) in `terraform/modules/control-plane/bootstrap.sh`
- **Stage 2 — Apply (CI)**: Push/merge triggers existing `.github/workflows/terraform-apply.yml`; the `user_data` hash change forces control plane instance replacement; new instance re-runs the corrected bootstrap
- **Stage 3 — Unblocks 003-2**: `kubeadm init` passes preflight and completes; the join command lands in SSM Parameter Store (AC-006 end-to-end proof)

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `grep -q 'modprobe br_netfilter' terraform/modules/control-plane/bootstrap.sh`
- **AC-003**: `grep -q 'net.bridge.bridge-nf-call-iptables = 1' terraform/modules/control-plane/bootstrap.sh`
- **AC-004**: `grep -q 'net.ipv4.ip_forward = 1' terraform/modules/control-plane/bootstrap.sh`
- **AC-005**: `! grep -q 'kind: KubeletConfiguration' terraform/modules/control-plane/bootstrap.sh`
- **AC-006**: `aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command --with-decryption --query 'Parameter.Value' --output text | grep -q 'kubeadm join'`

## 5. Risks & Mitigations

- **br_netfilter availability**: the module ships in the AL2023 kernel (`kernel-modules`, preinstalled); `modprobe` requires no package install
- **Sysctl persistence**: `/etc/sysctl.d/99-kubernetes.conf` is the standard drop-in location; `sysctl --system` applies it immediately and it survives reboots
- **KubeletConfiguration removal is behavior-neutral**: containerd already runs with `SystemdCgroup = true` and kubelet on AL2023 defaults to the systemd cgroup driver — the removed document was ignored by kubeadm anyway
- **Instance replacement is expected**: the `user_data` hash change forces a destroy + re-launch of the control plane; acceptable in the dev up/down test loop, and it guarantees the corrected script actually runs
- **Pinned version unchanged**: stays on kubeadm/kubelet/kubectl v1.28.0 — no version drift introduced by the fix
- **Rollback**: revert the `bootstrap.sh` change and re-apply (instance replaced again)
