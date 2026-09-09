# Execution Graph (DAG): Flannel SSM Poll Query Fix

**Input**: Design documents from `/specs/003-10-flannel-ssm-poll-query-fix/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~1 min (agent file edit) + CI verification

---

## Stage 1: Provisioner Correction

- [x] T001 [Stage 1: Provisioner] In `terraform/environments/dev/main.tf`: in the `local-exec` provisioner's `command` heredoc for `null_resource "apply_flannel_cni"`, change the status-poll `--query` argument (line 138) from `'CommandInvocation.Status'` to `'CommandInvocation.Status || Status'`. The `send-command`, the `Success`/`Failed`/`TimedOut`/`Cancelled` checks, the loop bounds, and the KUBECONFIG-prefixed `kubectl apply` (003-9) are byte-for-byte unchanged.

## Stage 2: Verification (CI-only)

- [ ] T002 [Stage 2: Static] AC-001: `terraform fmt -check -recursive && terraform validate`
- [ ] T003 [Stage 2: Static] AC-002: `grep -qF 'CommandInvocation.Status || Status' terraform/environments/dev/main.tf`
- [ ] T004 [Stage 2: Static] AC-003: `! grep -qF "'CommandInvocation.Status'" terraform/environments/dev/main.tf`
- [ ] T005 [Stage 2: Plan] AC-004: `terraform plan -detailed-exitcode` exits 0
- [ ] T006 [Stage 2: E2E] AC-005: Flannel daemonset rolled out (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

---

## Parallelization Notes

- T001 is the only agent task; T002-T006 are CI gates that run after the apply.
- T002-T004 are independent static checks and can run in parallel in CI.
- T005 (plan) and T006 (E2E) depend on the apply completing.
