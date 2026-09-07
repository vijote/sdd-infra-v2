# Architecture Delta: Flannel Local-Exec Bash Fix

**Branch**: `003-5-flannel-local-exec-bash-fix` | **Date**: 2026-09-06 | **Spec**: specs/003-5-flannel-local-exec-bash-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/environments/dev/main.tf` | Modify | Add `interpreter = ["/bin/bash", "-c"]` to the `local-exec` provisioner in `null_resource "apply_flannel_cni"` so the script runs under bash (supports `set -o pipefail`) instead of the default `/bin/sh` (dash) |

**No other files change.** The `command` heredoc (SSM send-command + poll loop) is byte-for-byte unchanged. All modules, the VPC, control plane, cluster plumbing, and workflows are untouched — this is a provisioner-interpreter-only correction.

## 2. Architectural Boundaries & Dependency Flow

- **Boundary**: The fix lives in the dev-environment Terraform wiring (003-3's `null_resource "apply_flannel_cni"`) — no resource change, no CloudFormation, no IAM change, no bootstrap change
- **Root cause (fatal)**: `local-exec` runs its command via `/bin/sh -c` by default. On GitHub's `ubuntu-latest` runner, `/bin/sh` is **dash**, which lacks `set -o pipefail`. The first line `set -euo pipefail` aborts with `Illegal option -o pipefail` (exit 2) before any `aws ssm` command runs — the Flannel CNI is never applied
- **Fix flow**: `interpreter = ["/bin/bash", "-c"]` → provisioner runs under bash → `set -euo pipefail` is valid → SSM send-command issues → poll loop waits for `Success` → Flannel manifest applied on the control plane
- **Consumers**:
  - 003-3 AC-005 verification → Flannel daemonset rolled out on the cluster
  - Downstream 003-3 worker pods depend on the CNI being present for pod networking
- **Null resource re-run**: changing the `interpreter` argument changes the provisioner's computed configuration, so Terraform re-runs the provisioner on the next apply — the SSM command is re-issued and the Flannel manifest is re-applied (idempotent `kubectl apply`)

## 3. Provisioning & Rollout Stages

- **Stage 1 — Provisioner edit (agent)**: Add `interpreter = ["/bin/bash", "-c"]` to the `local-exec` provisioner in `terraform/environments/dev/main.tf`
- **Stage 2 — Apply (CI)**: Push/merge triggers existing `.github/workflows/terraform-apply.yml`; the provisioner re-runs under bash, the SSM command is issued, and the Flannel CNI is applied to the control plane
- **Stage 3 — Unblocks 003-3**: the Flannel CNI daemonset is rolled out; AC-005 (daemonset rollout) is the end-to-end proof the provisioner ran to completion

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `grep -q 'interpreter = \["/bin/bash", "-c"\]' terraform/environments/dev/main.tf`
- **AC-003**: `grep -q 'set -euo pipefail' terraform/environments/dev/main.tf`
- **AC-004**: `terraform plan -detailed-exitcode`
- **AC-005**: Flannel daemonset rolled out (SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 5. Risks & Mitigations

- **Bash availability**: `/bin/bash` is present on GitHub's `ubuntu-latest` runner (Ubuntu 22.04+ ships bash by default); no additional package install required
- **Null resource re-run is expected**: the `interpreter` change forces the provisioner to re-run; the SSM command is re-issued and the Flannel manifest is re-applied — idempotent, no harm
- **No resource impact**: provisioner-config-only change; no instance replacement, no state drift beyond the null resource re-run
- **Alternative considered**: dropping `pipefail` → `set -eu` would also work (the script has no pipes), but `interpreter` is the documented Terraform mechanism and preserves the strict `pipefail` setting for future pipe additions
- **Rollback**: remove the `interpreter` line and re-apply (reverts to `/bin/sh`; only meaningful if the script is also changed to drop `pipefail`)
