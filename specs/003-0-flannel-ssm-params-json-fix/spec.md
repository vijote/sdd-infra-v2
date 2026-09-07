# Spec: Flannel SSM Params JSON Fix

**Feature Branch**: `003-0-flannel-ssm-params-json-fix` | **Date**: 2026-09-06 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform provisioner command escaping correction only — no new AWS resources, no resource changes
- **Kubernetes / Cluster Scope**: Worker nodes module (003-3-worker-nodes) — Flannel CNI application step
- **Target Service**: `terraform/environments/dev/main.tf` (`null_resource "apply_flannel_cni"` local-exec provisioner, `--parameters` argument)
- **Root Cause (fatal)**: `terraform apply` fails with `aws: [ERROR]: An error occurred (ParamValidation): Error parsing parameter '--parameters': Expected: ',', received: '"'`. The `--parameters` value is over-escaped: the file contains `\\\"` (three backslashes + quote) around each command string. Terraform heredocs pass backslashes through literally, so bash sees `\\\"`; inside bash double-quotes `\\\"` collapses to `\"` (backslash + quote). The AWS CLI therefore receives `commands=[\"curl ...\",\"kubectl ...\"]` — literal backslash-quotes, which is **invalid JSON** — and rejects it before any SSM command is sent.
- **Decision**: Reduce each `\\\"` to `\"` (one backslash + quote) in the `--parameters` argument. Terraform passes `\"` through; bash double-quote parsing collapses `\"` to a clean `"`; the AWS CLI receives valid JSON `commands=["curl ...","kubectl ..."]`.

### 1.1 Terraform Provisioner Command Contract

File: `terraform/environments/dev/main.tf`

**Before (broken — `\\\"` over-escape → AWS CLI gets `\"`):**

```hcl
        --parameters "commands=[\\\"curl -sSL $${FLANNEL_URL} -o /tmp/kube-flannel.yml\\\",\\\"kubectl apply -f /tmp/kube-flannel.yml\\\"]" \
```

**After (fixed — `\"` → AWS CLI gets `"`):**

```hcl
        --parameters "commands=[\"curl -sSL $${FLANNEL_URL} -o /tmp/kube-flannel.yml\",\"kubectl apply -f /tmp/kube-flannel.yml\"]" \
```

- **Escaping trace**: file `\"` → Terraform heredoc passes through → bash double-quote `\"` → `"` → AWS CLI JSON `commands=["curl ...","kubectl ..."]` (valid)
- **Four occurrences fixed**: the quote before `curl`, after the first `yml` (before the comma), before `kubectl`, and after the second `yml` (before `]`)
- **No other changes**: the `interpreter` line, the SSM send-command flags, the poll loop, and all other resources are byte-for-byte unchanged. Only the `--parameters` argument's inner quotes change.

### 1.2 Deployment Contract

- **Method**: Existing `.github/workflows/terraform-apply.yml` on main push — no new workflow, no local apply (constitution principles 5, 6, 8)
- **Effect**: `null_resource.apply_flannel_cni` is a null resource; changing the `command` string changes the provisioner configuration, forcing Terraform to re-run the provisioner on the next apply. The SSM command is re-issued with valid JSON, and the Flannel CNI manifest is applied
- **Rollback**: Revert the `--parameters` escaping and re-apply (re-introduces the `ParamValidation` error — rollback is only meaningful if re-paired with the original over-escape)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: `--parameters` uses single-backslash JSON quotes (`grep -qF 'commands=[\"' terraform/environments/dev/main.tf`)
- [ ] AC-003: Triple-backslash over-escape removed (`! grep -qF '\\\"' terraform/environments/dev/main.tf`)
- [ ] AC-004: Terraform plan generates expected resource delta without errors (`terraform plan -detailed-exitcode`)
- [ ] AC-005: Flannel CNI daemonset rolled out on the cluster (verified via SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 3. Assumptions & Constraints

- **Scope**: Provisioner-command-escaping-only correction; no change to SSM document, Flannel version, instance, or any Terraform resource
- **Heredoc backslash behavior**: Terraform `<<-EOT` heredocs do not process backslash escapes — backslashes reach the shell verbatim; only `${...}` (interpolate) and `$${...}` (literal `$`) are transformed
- **Bash double-quote behavior**: inside `"..."`, bash collapses `\"` → `"` and `\\` → `\`; this is why the file must contain exactly `\"` (not `\\\"`) to yield a clean JSON quote
- **Null resource re-run**: changing the `command` string forces the provisioner to re-run; the SSM command is re-issued and the Flannel manifest is re-applied (idempotent `kubectl apply`)
- **Ordering**: This spec MUST be applied before 003-3's Flannel CNI is considered deployed; AC-005 (daemonset rollout) is the end-to-end proof the SSM command was accepted and ran to completion
