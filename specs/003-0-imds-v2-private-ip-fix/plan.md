# Architecture Delta: IMDSv2 Private IP Fix

**Branch**: `003-0-imds-v2-private-ip-fix` | **Date**: 2026-09-05 | **Spec**: specs/003-0-imds-v2-private-ip-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/modules/control-plane/bootstrap.sh` | Modify | (A) Replace bare IMDS `curl` (line 16) with IMDSv2 token flow (PUT token + `X-aws-ec2-metadata-token` header) so `PRIVATE_IP` resolves; (B) correct KubeletConfiguration `apiVersion` from `kubeadm.k8s.io/v1beta3` to `kubelet.k8s.io/v1beta1` (line 68) |

**No other files change.** Terraform resources, dev environment, workflows, and all other modules are untouched — this is a bootstrap-script-only correction.

## 2. Architectural Boundaries & Dependency Flow

- **Boundary**: The fix lives in the node bootstrap layer (003-2's `bootstrap.sh`) — no Terraform resource change, no CloudFormation, no IAM change
- **Root cause (fatal)**: AL2023 enforces IMDSv2; the unauthenticated `curl` returns 401, `curl -s` swallows it, `PRIVATE_IP` is empty → `controlPlaneEndpoint: :6443` → `kubeadm init` fails with `hostport :6443: host '' must be a valid IP address`
- **Root cause (warning)**: KubeletConfiguration declared under the wrong GVK (`kubeadm.k8s.io/v1beta3`); kubeadm ignores the document and drops `cgroupDriver: systemd`
- **Fix flow**: IMDSv2 token → valid `PRIVATE_IP` → `controlPlaneEndpoint`/`advertiseAddress`/`certSANs` render correctly → `kubeadm init` succeeds → join command published to SSM
- **Consumers**:
  - 003-2 control plane user-data → `kubeadm init` (now succeeds) → `ssm put-parameter`
  - 003-3 workers (future) → read the join command from SSM
- **Instance replacement**: `user_data` is embedded in the instance; changing `bootstrap.sh` changes its hash, so Terraform **replaces** the control plane instance (destroy + re-launch) and the corrected bootstrap re-runs at first boot

## 3. Provisioning & Rollout Stages

- **Stage 1 — Script edit (agent)**: Apply Fix A (IMDSv2 token flow) and Fix B (KubeletConfiguration GVK) in `terraform/modules/control-plane/bootstrap.sh`
- **Stage 2 — Apply (CI)**: Push/merge triggers existing `.github/workflows/terraform-apply.yml`; the `user_data` hash change forces control plane instance replacement; new instance re-runs the corrected bootstrap
- **Stage 3 — Unblocks 003-2**: `kubeadm init` completes and the join command lands in SSM Parameter Store (AC-005 end-to-end proof)

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `grep -q 'X-aws-ec2-metadata-token-ttl-seconds' terraform/modules/control-plane/bootstrap.sh`
- **AC-003**: `grep -q 'X-aws-ec2-metadata-token: ${IMDS_TOKEN}' terraform/modules/control-plane/bootstrap.sh`
- **AC-004**: `grep -q 'apiVersion: kubelet.k8s.io/v1beta1' terraform/modules/control-plane/bootstrap.sh`
- **AC-005**: `aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command --with-decryption --query 'Parameter.Value' --output text | grep -q 'kubeadm join'`

## 5. Risks & Mitigations

- **IMDSv2 is the AL2023 default**: the token flow works in both `optional` and `required` IMDS modes; no `ec2metadata` service setting change is needed
- **Instance replacement is expected**: the `user_data` hash change forces a destroy + re-launch of the control plane; acceptable in the dev up/down test loop, and it guarantees the corrected script actually runs
- **Pinned version unchanged**: stays on kubeadm/kubelet/kubectl v1.28.0 — no version drift introduced by the fix
- **KubeletConfiguration GVK**: `kubelet.k8s.io/v1beta1` is correct for kubeadm v1.28; the `cgroupDriver: systemd` value is redundant with the containerd `SystemdCgroup = true` setting but is now actually honored (removes the warning)
- **Rollback**: revert the `bootstrap.sh` change and re-apply (instance replaced again)
