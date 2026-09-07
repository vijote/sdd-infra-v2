# Execution Graph (DAG): Flannel Wait Bootstrap Complete

**Input**: Design documents from `/specs/003-7-flannel-wait-bootstrap-complete/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~4 min (agent file edits) + CI verification

---

## Stage 1: Bootstrap-Complete Gate

- [x] T001 [Stage 1: Provisioner] In `terraform/environments/dev/main.tf`: in the `local-exec` provisioner's `command` heredoc for `null_resource "apply_flannel_cni"`, (1) at the start (after `FLANNEL_URL` is set, before the 003-4 SSM-agent wait), add `aws ssm delete-parameter --name "/sdd-k8s-platform/kubeadm-join-command" 2>/dev/null || true` to clear any stale join-command parameter from a previous run; (2) after the 003-4 SSM-agent wait and **before** `aws ssm send-command`, insert a bootstrap-complete wait — poll `aws ssm get-parameter --name "/sdd-k8s-platform/kubeadm-join-command" --with-decryption --query 'Parameter.Value' --output text` (60 iterations × 10s) until non-empty (control plane bootstrap finished); if empty after timeout, `exit 1` with `Control plane bootstrap did not complete within timeout` (the 003-4 agent wait, `--parameters` JSON, SSM flags, and existing poll loop are unchanged)
- [x] T002 [Stage 1: Worker] In `terraform/modules/worker-nodes/bootstrap.sh`: replace the single-shot `aws ssm get-parameter` + `exit 1` with a poll loop (60 iterations × 10s) that waits for the control plane to publish the join command before `eval`-ing it; keep the `exit 1` for the timeout case (the rest of the bootstrap is unchanged)

**Note**: the control plane bootstrap is **unchanged** — it already publishes the join command as its last step (the signal). The stale-signal cleanup lives in the Flannel provisioner (CI runner) because the control plane only installs the AWS CLI at ~line 45 (too late to clear a stale parameter before the provisioner's ~20-30s poll begins).

---

## Stage 2: Verification (CI-only — executed in GitHub Actions, never locally)

- [ ] T003 [Stage 2: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T001, T002)
- [ ] T004 [Stage 2: Verify] AC-002: Flannel provisioner waits for bootstrap-complete signal (`grep -q 'kubeadm-join-command' terraform/environments/dev/main.tf`) (Depends on T003)
- [ ] T005 [Stage 2: Verify] AC-003: Flannel provisioner deletes stale parameter before polling (`grep -q 'delete-parameter' terraform/environments/dev/main.tf`) (Depends on T004)
- [ ] T006 [Stage 2: Verify] AC-004: Worker bootstrap polls for join command (`grep -q 'seq 1 60' terraform/modules/worker-nodes/bootstrap.sh`) (Depends on T005)
- [ ] T007 [Stage 2: Verify] AC-005: Terraform plan generates expected resource delta without errors (`terraform plan -detailed-exitcode`) (Depends on T006)
- [ ] T008 [Stage 2: Verify] AC-006: Flannel CNI daemonset rolled out on the cluster (SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`) (Depends on T007)

---

## Dependencies / Execution Order

```
T001 ─┬─ T003 ─ T004 ─ T005 ─ T006 ─ T007 ─ T008
T002 ─┘
```

- **Parallel**: T001 and T002 are independent file edits (different files) — can be done in any order
- **Sequential**: T003 → T004 → T005 → T006 → T007 → T008 (static checks → clean plan → daemonset rollout)
- **Ordering constraint**: T007 (clean plan) confirms the config is valid; T008 (daemonset rollout) is the end-to-end proof the Flannel command ran to completion **after** bootstrap

## Notes

- **File mapping**: T001 → `dev/main.tf`, T002 → `worker-nodes/bootstrap.sh` (one file each)
- **No Terraform resource changes**: provisioner + worker-bootstrap corrections only — workers re-launch (user_data hash change), no type/subnet/IAM change; control plane unchanged
- **Deployment**: applied by the existing `.github/workflows/terraform-apply.yml` on main push — no local apply (constitution principles 5, 6, 8)
- **Verification**: Stage 2 tasks run in GitHub Actions CI only — never locally
- **Signal reference**: the join-command parameter is deleted by the Flannel provisioner at the start of the apply and published by the control plane bootstrap at its end (after `kubeadm init` + kubeconfig copy) — its presence means `kubectl` is installed and the API server is up
