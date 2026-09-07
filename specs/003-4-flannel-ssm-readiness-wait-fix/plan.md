# Architecture Delta: Flannel SSM Readiness Wait Fix

**Branch**: `003-4-flannel-ssm-readiness-wait-fix` | **Date**: 2026-09-06 | **Spec**: specs/003-4-flannel-ssm-readiness-wait-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/environments/dev/main.tf` | Modify | In `null_resource "apply_flannel_cni"`'s local-exec `command`: insert a readiness-wait loop (poll `aws ssm describe-instance-information` until the control plane's SSM agent registers, 30×10s) **before** the `aws ssm send-command` call, so the command is only sent once the instance is a valid SSM target |

**No other files change.** The `interpreter` line, the `--parameters` JSON (already fixed), the SSM send-command flags, and the existing invocation poll loop are byte-for-byte unchanged — this is a command-insertion-only correction.

## 2. Architectural Boundaries & Dependency Flow

- **Boundary**: The fix lives in the dev-environment Terraform wiring (003-3's `null_resource "apply_flannel_cni"`) — no resource change, no CloudFormation, no IAM change, no bootstrap change
- **Root cause (fatal)**: the provisioner calls `send-command` exactly once, immediately after the worker nodes are created. The control plane is freshly launched each run (instance ID differs across runs). The SSM agent registers **after** the EC2 `running` state Terraform waits for (lags ~30-90s), so `send-command` fires before the agent is registered → `InvalidInstanceId: Instances not in a valid state`
- **Fix flow**: readiness loop polls `describe-instance-information --filters "Key=InstanceIds,Values=<id>"` → empty until the agent registers → once `InstanceInformationList[0].InstanceId` equals the instance ID, the agent is a valid SSM target → `send-command` proceeds → Flannel manifest applied
- **Consumers**:
  - 003-3 AC-005 verification → Flannel daemonset rolled out on the cluster
  - Downstream 003-3 worker pods depend on the CNI being present for pod networking
- **Null resource re-run**: changing the `command` string changes the provisioner's computed configuration, so Terraform re-runs the provisioner on the next apply — the SSM command is re-issued and the Flannel manifest is re-applied (idempotent `kubectl apply`)

## 3. Provisioning & Rollout Stages

- **Stage 1 — Command edit (agent)**: Insert the SSM readiness-wait loop before `send-command` in `terraform/environments/dev/main.tf`
- **Stage 2 — Apply (CI)**: Push/merge triggers existing `.github/workflows/terraform-apply.yml`; the provisioner waits for SSM registration, then sends the command, and the Flannel CNI is applied to the control plane
- **Stage 3 — Unblocks 003-3**: the Flannel CNI daemonset is rolled out; AC-005 (daemonset rollout) is the end-to-end proof the SSM command was accepted and ran to completion

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `grep -q 'describe-instance-information' terraform/environments/dev/main.tf`
- **AC-003**: `grep -q 'SSM agent did not register' terraform/environments/dev/main.tf`
- **AC-004**: `terraform plan -detailed-exitcode`
- **AC-005**: Flannel daemonset rolled out (SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 5. Risks & Mitigations

- **SSM agent registration lag**: the agent is a systemd service that registers asynchronously at boot; the wait loop (30×10s = 300s) bridges the gap between EC2 `running` and SSM registration
- **Network is not the issue**: the control plane already reaches SSM (it published the join command via `aws ssm put-parameter` in 003-2), so outbound SSM connectivity via NAT is confirmed; the failure is purely a registration-timing race
- **`describe-instance-information` semantics**: a non-matching filter returns an empty `InstanceInformationList` (exit 0); the JMESPath query yields `None`, which the loop treats as "not yet registered"
- **Timeout guard**: if the agent does not register within 300s, the provisioner fails with a clear error (`SSM agent did not register`) instead of a confusing `InvalidInstanceId`
- **Null resource re-run is expected**: the `command` change forces the provisioner to re-run; the SSM command is re-issued and the Flannel manifest is re-applied — idempotent, no harm
- **No resource impact**: command-string-only change; no instance replacement, no state drift beyond the null resource re-run
- **Rollback**: remove the readiness-wait block and re-apply (re-introduces the `InvalidInstanceId` race)
