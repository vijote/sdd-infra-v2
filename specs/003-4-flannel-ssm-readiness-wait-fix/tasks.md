# Execution Graph (DAG): Flannel SSM Readiness Wait Fix

**Input**: Design documents from `/specs/003-4-flannel-ssm-readiness-wait-fix/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~3 min (agent file edit) + CI verification

---

## Stage 1: Provisioner Readiness Wait

- [x] T001 [Stage 1: Provisioner] In `terraform/environments/dev/main.tf`: in the `local-exec` provisioner's `command` heredoc for `null_resource "apply_flannel_cni"`, insert a readiness-wait loop **before** the `aws ssm send-command` call — poll `aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$${INSTANCE_ID}" --query 'InstanceInformationList[0].InstanceId' --output text` (30 iterations × 10s) until the returned ID equals `$${INSTANCE_ID}` (SSM agent registered); if it never registers, `exit 1` with `SSM agent did not register` (the `interpreter` line, `--parameters` JSON, SSM flags, and existing poll loop are unchanged)

---

## Stage 2: Verification (CI-only — executed in GitHub Actions, never locally)

- [ ] T002 [Stage 2: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T001)
- [ ] T003 [Stage 2: Verify] AC-002: SSM readiness wait present (`grep -q 'describe-instance-information' terraform/environments/dev/main.tf`) (Depends on T002)
- [ ] T004 [Stage 2: Verify] AC-003: SSM registration timeout guard present (`grep -q 'SSM agent did not register' terraform/environments/dev/main.tf`) (Depends on T003)
- [ ] T005 [Stage 2: Verify] AC-004: Terraform plan generates expected resource delta without errors (`terraform plan -detailed-exitcode`) (Depends on T004)
- [ ] T006 [Stage 2: Verify] AC-005: Flannel CNI daemonset rolled out on the cluster (SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`) (Depends on T005)

---

## Dependencies / Execution Order

```
T001 ─ T002 ─ T003 ─ T004 ─ T005 ─ T006
```

- **Sequential**: T001 → T002 → T003 → T004 → T005 → T006 (edit → static checks → clean plan → daemonset rollout)
- **Ordering constraint**: T005 (clean plan) confirms the provisioner config is valid; T006 (daemonset rollout) is the end-to-end proof the SSM command was accepted (agent registered) and ran to completion

## Notes

- **1:1 file mapping**: T001 touches exactly one file (constitution DAG principle) — the `local-exec` provisioner command in `null_resource "apply_flannel_cni"`
- **No Terraform resource changes**: command-insertion-only correction — the null resource re-runs (SSM command re-issued), no instance replacement, no state drift
- **Deployment**: applied by the existing `.github/workflows/terraform-apply.yml` on main push — no local apply (constitution principles 5, 6, 8)
- **Verification**: Stage 2 tasks run in GitHub Actions CI only — never locally
- **Readiness reference**: `describe-instance-information` returns the instance only once the SSM agent has registered; before that the filtered list is empty and the query yields `None`
