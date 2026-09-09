# Spec: Flannel SSM Poll Query Fix

**Feature Branch**: `003-10-flannel-ssm-poll-query-fix` | **Date**: 2026-09-09 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform provisioner command correction only — no new AWS resources, no resource changes
- **Kubernetes Scope**: None (Flannel CNI apply is unchanged; only the status-poll query is corrected)
- **AWS Scope**: SSM Run Command read-only (the `get-command-invocation` JMESPath query is corrected)
- **Terraform Scope**: `terraform/environments/dev/main.tf` — `null_resource "apply_flannel_cni"` `local-exec` provisioner, status-poll loop (line 138)

## 2. Problem Statement

The Flannel provisioner sends an SSM Run Command, then polls for its status in a 60×10s loop:

```
STATUS=$(aws ssm get-command-invocation \
  --instance-id "$${INSTANCE_ID}" \
  --command-id "$${CMD_ID}" \
  --query 'CommandInvocation.Status' --output text 2>/dev/null) || STATUS="Pending"
```

The command **succeeds** (Flannel daemonset created, `ResponseCode: 0`, `ExecutionElapsedTime:
PT0.913S`), but the provisioner reports `Flannel CNI apply timed out waiting for invocation`.

**Root cause**: the `--query 'CommandInvocation.Status'` JMESPath expression does not match the
actual response shape. The `aws ssm get-command-invocation` response is **flat** — `Status` is a
top-level key, with **no `CommandInvocation` wrapper**:

```json
{
  "CommandId": "8c7c33aa-...",
  "Status": "Success",
  "ResponseCode": 0,
  "ExecutionElapsedTime": "PT0.913S",
  "StandardOutputContent": "namespace/kube-flannel created\n...daemonset.apps/kube-flannel-ds created\n"
}
```

Querying `CommandInvocation.Status` on this flat object returns `null` → `STATUS` is empty → it
never equals `Success` → the loop exhausts 600s → `timed out waiting for invocation`. The command
succeeded in <1s; the provisioner was blind to it.

**Confirmed by direct probe** (control plane `i-0ec4855dc1898b061`, command `8c7c33aa`):
`list-command-invocations` shows `Status: Success`; `get-command-invocation --output json` returns
the flat object above with `Status: Success` at the top level.

This is unrelated to the 003-9 KUBECONFIG fix (which is correct and is what made the command
succeed) and to the 003-7 bootstrap gate (which already passed).

## 3. Solution

Correct the JMESPath query to read the top-level `Status`, while remaining safe if a different
CLI version returns the wrapped shape:

```
--query 'CommandInvocation.Status || Status'
```

JMESPath `||` returns `CommandInvocation.Status` if that path exists, otherwise `Status`. This is
correct for both the flat response observed here and the wrapped shape documented in the AWS CLI
reference.

- **No other change**: the `send-command`, the `Success`/`Failed`/`TimedOut`/`Cancelled` checks,
  the loop bounds, and the KUBECONFIG-prefixed `kubectl apply` (003-9) are byte-for-byte unchanged.
- **No IAM change**: `ssm:GetCommandInvocation` is already granted.
- **No heredoc escaping needed**: the new query string contains no `$` characters.

## 4. Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: The corrected query is present (`grep -qF 'CommandInvocation.Status || Status' terraform/environments/dev/main.tf`)
- [ ] AC-003: The old flat-mismatched query is gone (`! grep -qF "'CommandInvocation.Status'" terraform/environments/dev/main.tf`)
- [ ] AC-004: `terraform plan -detailed-exitcode` exits 0 (no resource changes; only the provisioner command changes)
- [ ] AC-005: Flannel daemonset rolled out (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 5. Out of Scope

- No changes to the control-plane or worker-nodes modules
- No changes to the SSM-agent readiness wait (003-4), the JSON escaping (003-6), the bootstrap-complete gate (003-7), or the KUBECONFIG prefix (003-9)
- No changes to the Flannel manifest URL or version pin
- No changes to the `delete-parameter` step (003-8 — deferred)
