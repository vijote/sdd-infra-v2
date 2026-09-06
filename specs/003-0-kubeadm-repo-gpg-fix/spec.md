# Spec: Kubeadm Repo GPG Fix

**Feature Branch**: `003-0-kubeadm-repo-gpg-fix` | **Date**: 2026-09-05 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Bootstrap script correction only — no new AWS resources, no Terraform resource changes
- **Kubernetes / Cluster Scope**: Control plane node bootstrap (003-2-control-plane)
- **Target Service**: `terraform/modules/control-plane/bootstrap.sh` (EC2 user-data, runs once at first boot)
- **Root Cause**: Line 27 uses `dnf config-manager --add-repo <url>`, which writes a minimal `.repo` entry **without a `gpgkey` line**. The subsequent `dnf install -y kubelet kubeadm kubectl` (line 28) then fails with `Error: GPG check FAILED` because dnf cannot verify package signatures. The script aborts here (before `kubeadm init`), so no join command is ever published to SSM Parameter Store.
- **Decision**: Replace the `--add-repo` line with an explicit `/etc/yum.repos.d/kubernetes.repo` file that declares `gpgcheck=1` and the official `gpgkey` URL for the v1.28 stable repo.

### 1.1 Bootstrap Script Contract

File: `terraform/modules/control-plane/bootstrap.sh`

Replace line 27:

```bash
dnf config-manager --add-repo https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
```

with an explicit repo file:

```bash
cat <<'EOF' > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF
```

- **Line 28** (`dnf install -y kubelet-${K8S_VERSION} kubeadm-${K8S_VERSION} kubectl-${K8S_VERSION}`): unchanged — now succeeds because the repo declares its GPG key
- **All other lines**: unchanged (containerd, AWS CLI install, kubeadm config, `kubeadm init`, SSM publish)
- **No Terraform changes**: the module's `main.tf` already references `bootstrap.sh` via `user_data = file("${path.module}/bootstrap.sh")`; only the script content changes

### 1.2 Deployment Contract

- **Method**: Existing `.github/workflows/terraform-apply.yml` on main push — no new workflow, no local apply (constitution principles 5, 6, 8)
- **Effect**: `user_data` is a computed attribute of the instance; changing `bootstrap.sh` changes the `user_data` hash, forcing **replacement** of the control plane instance (destroy + re-launch). The new instance re-runs the corrected bootstrap at first boot
- **Rollback**: Revert the `bootstrap.sh` change and re-apply (instance replaced again)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Repo file declares the GPG key (`grep -q 'gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key' terraform/modules/control-plane/bootstrap.sh`)
- [ ] AC-003: Repo file enables GPG checking (`grep -q 'gpgcheck=1' terraform/modules/control-plane/bootstrap.sh`)
- [ ] AC-004: The bare `--add-repo` line is removed (`! grep -q 'config-manager --add-repo' terraform/modules/control-plane/bootstrap.sh`)
- [ ] AC-005: Join command published to SSM after re-launch (`aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command --with-decryption --query 'Parameter.Value' --output text | grep -q 'kubeadm join'`)

## 3. Assumptions & Constraints

- **Scope**: Single-line-class fix to the bootstrap script; no change to instance type, subnet, IAM, or kubeadm version (stays v1.28.0)
- **Instance replacement**: Because `user_data` is embedded in the instance, the fix requires the control plane instance to be destroyed and re-launched — expected and acceptable in the dev up/down test loop
- **GPG key URL**: `repomd.xml.key` is the canonical key location for the `pkgs.k8s.io` OBS-based repos; `gpgcheck=1` keeps signature verification on (no `gpgcheck=0` bypass)
- **Ordering**: This spec MUST be applied before 003-2's control plane is considered healthy; the join command (AC-005) is the end-to-end proof the corrected bootstrap ran to completion
