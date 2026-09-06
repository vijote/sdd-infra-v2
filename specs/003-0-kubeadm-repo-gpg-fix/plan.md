# Architecture Delta: Kubeadm Repo GPG Fix

**Branch**: `003-0-kubeadm-repo-gpg-fix` | **Date**: 2026-09-05 | **Spec**: specs/003-0-kubeadm-repo-gpg-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/modules/control-plane/bootstrap.sh` | Modify | Replace `dnf config-manager --add-repo <url>` (line 27) with an explicit `/etc/yum.repos.d/kubernetes.repo` heredoc declaring `gpgcheck=1` + `gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key` |

**No other files change.** Terraform resources, dev environment, workflows, and all other modules are untouched — this is a bootstrap-script-only correction.

## 2. Architectural Boundaries & Dependency Flow

- **Boundary**: The fix lives in the node bootstrap layer (003-2's `bootstrap.sh`) — no Terraform resource change, no CloudFormation, no IAM change
- **Root cause**: `dnf config-manager --add-repo` writes a minimal `.repo` entry with **no `gpgkey` line**; `dnf install kubelet/kubeadm/kubectl` then fails `GPG check FAILED` and the script aborts before `kubeadm init`
- **Fix flow**: explicit repo file → dnf verifies package signatures → `kubeadm init` runs → join command published to SSM
- **Consumers**:
  - 003-2 control plane user-data → installs kubeadm v1.28.0 (now succeeds) → `kubeadm init` → `ssm put-parameter`
  - 003-3 workers (future) → read the join command from SSM
- **Instance replacement**: `user_data` is embedded in the instance; changing `bootstrap.sh` changes its hash, so Terraform **replaces** the control plane instance (destroy + re-launch) and the corrected bootstrap re-runs at first boot

## 3. Provisioning & Rollout Stages

- **Stage 1 — Script edit (agent)**: Replace the `--add-repo` line in `terraform/modules/control-plane/bootstrap.sh` with the explicit repo-file heredoc
- **Stage 2 — Apply (CI)**: Push/merge triggers existing `.github/workflows/terraform-apply.yml`; the `user_data` hash change forces control plane instance replacement; new instance re-runs the corrected bootstrap
- **Stage 3 — Unblocks 003-2**: `kubeadm init` completes and the join command lands in SSM Parameter Store (AC-005 end-to-end proof)

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `grep -q 'gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key' terraform/modules/control-plane/bootstrap.sh`
- **AC-003**: `grep -q 'gpgcheck=1' terraform/modules/control-plane/bootstrap.sh`
- **AC-004**: `! grep -q 'config-manager --add-repo' terraform/modules/control-plane/bootstrap.sh`
- **AC-005**: `aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command --with-decryption --query 'Parameter.Value' --output text | grep -q 'kubeadm join'`

## 5. Risks & Mitigations

- **GPG verification stays ON**: `gpgcheck=1` with the official key URL — no `gpgcheck=0` bypass, so package integrity is still enforced
- **Instance replacement is expected**: the `user_data` hash change forces a destroy + re-launch of the control plane; acceptable in the dev up/down test loop, and it guarantees the corrected script actually runs
- **Pinned version unchanged**: stays on kubeadm/kubelet/kubectl v1.28.0 and the v1.28 stable repo — no version drift introduced by the fix
- **Rollback**: revert the `bootstrap.sh` change and re-apply (instance replaced again)
