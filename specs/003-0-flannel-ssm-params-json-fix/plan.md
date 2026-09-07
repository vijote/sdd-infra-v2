# Architecture Delta: Flannel SSM Params JSON Fix

**Branch**: `003-0-flannel-ssm-params-json-fix` | **Date**: 2026-09-06 | **Spec**: specs/003-0-flannel-ssm-params-json-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/environments/dev/main.tf` | Modify | In `null_resource "apply_flannel_cni"`'s local-exec `command`: reduce the four `\\\"` (triple-backslash + quote) escapes in the `--parameters` argument to `\"` (single-backslash + quote) so the AWS CLI receives valid JSON `commands=["curl ...","kubectl ..."]` |

**No other files change.** The `interpreter` line, SSM send-command flags, poll loop, and all other resources are byte-for-byte unchanged — this is a command-escaping-only correction.

## 2. Architectural Boundaries & Dependency Flow

- **Boundary**: The fix lives in the dev-environment Terraform wiring (003-3's `null_resource "apply_flannel_cni"`) — no resource change, no CloudFormation, no IAM change, no bootstrap change
- **Root cause (fatal)**: the `--parameters` value is over-escaped. Escaping trace: file `\\\"` → Terraform heredoc passes backslashes through verbatim → bash double-quote parsing collapses `\\\"` to `\"` → AWS CLI receives `commands=[\"curl ...\",\"kubectl ...\"]` (literal backslash-quotes) → invalid JSON → `ParamValidation: Expected: ',', received: '"'`
- **Fix flow**: file `\"` → heredoc passes through → bash collapses `\"` to `"` → AWS CLI receives `commands=["curl ...","kubectl ..."]` (valid JSON) → SSM accepts the command → Flannel manifest applied on the control plane
- **Consumers**:
  - 003-3 AC-005 verification → Flannel daemonset rolled out on the cluster
  - Downstream 003-3 worker pods depend on the CNI being present for pod networking
- **Null resource re-run**: changing the `command` string changes the provisioner's computed configuration, so Terraform re-runs the provisioner on the next apply — the SSM command is re-issued and the Flannel manifest is re-applied (idempotent `kubectl apply`)

## 3. Provisioning & Rollout Stages

- **Stage 1 — Command edit (agent)**: Reduce the four `\\\"` escapes to `\"` in the `--parameters` argument in `terraform/environments/dev/main.tf`
- **Stage 2 — Apply (CI)**: Push/merge triggers existing `.github/workflows/terraform-apply.yml`; the provisioner re-runs, the SSM command is accepted (valid JSON), and the Flannel CNI is applied to the control plane
- **Stage 3 — Unblocks 003-3**: the Flannel CNI daemonset is rolled out; AC-005 (daemonset rollout) is the end-to-end proof the SSM command was accepted and ran to completion

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `grep -qF 'commands=[\"' terraform/environments/dev/main.tf`
- **AC-003**: `! grep -qF '\\\"' terraform/environments/dev/main.tf`
- **AC-004**: `terraform plan -detailed-exitcode`
- **AC-005**: Flannel daemonset rolled out (SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 5. Risks & Mitigations

- **Heredoc backslash behavior**: Terraform `<<-EOT` heredocs do not process backslash escapes — backslashes reach the shell verbatim; only `${...}` (interpolate) and `$${...}` (literal `$`) are transformed. This is why the file must contain exactly `\"` to yield a clean JSON quote
- **Bash double-quote behavior**: inside `"..."`, bash collapses `\"` → `"` and `\\` → `\`; the fix relies on this documented behavior
- **Null resource re-run is expected**: the `command` change forces the provisioner to re-run; the SSM command is re-issued and the Flannel manifest is re-applied — idempotent, no harm
- **No resource impact**: command-string-only change; no instance replacement, no state drift beyond the null resource re-run
- **Rollback**: revert the `--parameters` escaping and re-apply (re-introduces the `ParamValidation` error)
