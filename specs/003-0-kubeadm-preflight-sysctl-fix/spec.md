# Spec: Kubeadm Preflight Sysctl Fix

**Feature Branch**: `003-0-kubeadm-preflight-sysctl-fix` | **Date**: 2026-09-05 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Bootstrap script correction only — no new AWS resources, no Terraform resource changes
- **Kubernetes / Cluster Scope**: Control plane node bootstrap (003-2-control-plane)
- **Target Service**: `terraform/modules/control-plane/bootstrap.sh` (EC2 user-data, runs once at first boot)
- **Root Cause (fatal)**: `kubeadm init` preflight fails with two fatal errors: (1) `/proc/sys/net/bridge/bridge-nf-call-iptables does not exist` — the `br_netfilter` kernel module is not loaded, so the proc file is absent; (2) `/proc/sys/net/ipv4/ip_forward contents are not set to 1` — IP forwarding is disabled. Both are standard kubeadm kernel requirements that the bootstrap must satisfy before `kubeadm init`.
- **Root Cause (warning)**: The kubeadm config file contains a `KubeletConfiguration` document that kubeadm ignores (`WARNING: Ignored YAML document ... Kind=KubeletConfiguration`). The document is also **redundant**: containerd is already configured with `SystemdCgroup = true` (line 22) and kubelet on AL2023 defaults to the systemd cgroup driver.
- **Decision**: (A) Load `br_netfilter` and write a persistent sysctl file (`/etc/sysctl.d/99-kubernetes.conf`) with `net.bridge.bridge-nf-call-iptables = 1`, `net.bridge.bridge-nf-call-ip6tables = 1`, `net.ipv4.ip_forward = 1`, then apply via `sysctl --system` — all before `kubeadm init`. (B) Remove the KubeletConfiguration document from the kubeadm config entirely (eliminates the warning and the dead config; no behavior change).

### 1.1 Bootstrap Script Contract

File: `terraform/modules/control-plane/bootstrap.sh`

**Fix A — kernel module + sysctls (insert before the `kubeadm init` section, after the AWS CLI install):**

```bash
# --- Load br_netfilter and enable required sysctls (kubeadm preflight requirements) ---
modprobe br_netfilter
cat <<'EOF' > /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
```

- **Placement**: after the AWS CLI install block (line 45), before the kubeadm config write (line 47)
- **Persistence**: the sysctl file under `/etc/sysctl.d/` survives reboots; `modprobe` is re-run on every boot by the user-data (single-boot script, acceptable for dev)

**Fix B — remove KubeletConfiguration document (delete lines 70–73):**

```bash
---
apiVersion: kubelet.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
```

- The kubeadm config heredoc ends after the `ClusterConfiguration` document (line 69, `- 127.0.0.1`), followed by `EOF`
- **All other lines**: unchanged (IMDSv2 private IP, containerd, kubernetes repo, AWS CLI, `kubeadm init`, SSM publish)
- **No Terraform changes**: the module's `main.tf` already references `bootstrap.sh` via `user_data = file("${path.module}/bootstrap.sh")`; only the script content changes

### 1.2 Deployment Contract

- **Method**: Existing `.github/workflows/terraform-apply.yml` on main push — no new workflow, no local apply (constitution principles 5, 6, 8)
- **Effect**: `user_data` is a computed attribute of the instance; changing `bootstrap.sh` changes the `user_data` hash, forcing **replacement** of the control plane instance (destroy + re-launch). The new instance re-runs the corrected bootstrap at first boot
- **Rollback**: Revert the `bootstrap.sh` change and re-apply (instance replaced again)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: br_netfilter module is loaded (`grep -q 'modprobe br_netfilter' terraform/modules/control-plane/bootstrap.sh`)
- [ ] AC-003: Sysctl file enables bridge netfilter (`grep -q 'net.bridge.bridge-nf-call-iptables = 1' terraform/modules/control-plane/bootstrap.sh`)
- [ ] AC-004: Sysctl file enables IP forwarding (`grep -q 'net.ipv4.ip_forward = 1' terraform/modules/control-plane/bootstrap.sh`)
- [ ] AC-005: KubeletConfiguration document removed (`! grep -q 'kind: KubeletConfiguration' terraform/modules/control-plane/bootstrap.sh`)
- [ ] AC-006: Join command published to SSM after re-launch (`aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command --with-decryption --query 'Parameter.Value' --output text | grep -q 'kubeadm join'`)

## 3. Assumptions & Constraints

- **Scope**: Bootstrap-script-only correction; no change to instance type, subnet, IAM, or kubeadm version (stays v1.28.0)
- **br_netfilter availability**: the module ships in the AL2023 kernel (`kernel-modules` package, preinstalled); `modprobe` requires no package install
- **Sysctl persistence**: `/etc/sysctl.d/99-kubernetes.conf` is the standard location; `sysctl --system` applies all drop-in files, so the values take effect immediately and survive reboots
- **KubeletConfiguration removal is behavior-neutral**: containerd already runs with `SystemdCgroup = true` (line 22) and kubelet on AL2023 defaults to the systemd cgroup driver — the removed document was ignored by kubeadm anyway
- **Instance replacement**: because `user_data` is embedded in the instance, the fix requires the control plane instance to be destroyed and re-launched — expected and acceptable in the dev up/down test loop
- **Ordering**: This spec MUST be applied before 003-2's control plane is considered healthy; the join command (AC-006) is the end-to-end proof the corrected bootstrap ran to completion
