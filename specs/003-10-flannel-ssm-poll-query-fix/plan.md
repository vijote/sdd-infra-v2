# Architecture Delta: Flannel SSM Poll Query Fix

**Branch**: `003-10-flannel-ssm-poll-query-fix` | **Date**: 2026-09-09 | **Spec**: specs/003-10-flannel-ssm-poll-query-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/environments/dev/main.tf` | Modify | In the `local-exec` provisioner of `null_resource "apply_flannel_cni"`, change the status-poll `--query` from `'CommandInvocation.Status'` to `'CommandInvocation.Status \|\| Status'` (line 138). No other change. |

## 2. Architecture Delta

The Flannel provisioner's status-poll query changes from a wrapped-shape path to one that also
reads the flat top-level `Status`:

- **Before**: `--query 'CommandInvocation.Status'` — returns `null` on the flat
  `get-command-invocation` response (no `CommandInvocation` wrapper), so `STATUS` is always empty
  and the loop times out even though the command succeeded.
- **After**: `--query 'CommandInvocation.Status || Status'` — JMESPath `||` returns
  `CommandInvocation.Status` if present, else the top-level `Status`. Correct for both the flat
  response observed and the wrapped shape in the AWS CLI docs.

No resource graph changes. The `send-command`, the `Success`/`Failed`/`TimedOut`/`Cancelled`
checks, the loop bounds, and the KUBECONFIG-prefixed `kubectl apply` (003-9) are byte-for-byte
unchanged. Only the `--query` argument on line 138 changes.

## 3. Rollout Stages

1. **Provisioner edit (agent)** — change the `--query` argument on line 138 of
   `terraform/environments/dev/main.tf`.
2. **Static verification (CI)** — `terraform fmt -check -recursive && terraform validate`;
   grep gates (AC-002/AC-003); `terraform plan -detailed-exitcode` (AC-004).
3. **End-to-end verification (CI)** — apply runs; the provisioner sends the Flannel command, the
   poll loop now reads the real `Status`, sees `Success`, and exits 0; the Flannel daemonset rolls
   out (AC-005).

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `grep -qF 'CommandInvocation.Status || Status' terraform/environments/dev/main.tf`
- **AC-003**: `! grep -qF "'CommandInvocation.Status'" terraform/environments/dev/main.tf`
- **AC-004**: `terraform plan -detailed-exitcode`
- **AC-005**: Flannel daemonset rolled out (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| A different AWS CLI version returns the wrapped shape | The `||` fallback (`CommandInvocation.Status \|\| Status`) handles both flat and wrapped |
| The query still returns empty for a genuinely pending command | The existing `|| STATUS="Pending"` fallback and the 600s timeout are unchanged |
| The command actually failed but the loop now sees it | The `Failed`/`TimedOut`/`Cancelled` branch (line 143) is unchanged and will now correctly fire |
