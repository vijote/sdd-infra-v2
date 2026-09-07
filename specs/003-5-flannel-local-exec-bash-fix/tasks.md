# Execution Graph (DAG): Flannel Local-Exec Bash Fix

**Input**: Design documents from `/specs/003-5-flannel-local-exec-bash-fix/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~2 min (agent file edit) + CI verification

---

## Stage 1: Provisioner Interpreter Correction

- [x] T001 [Stage 1: Provisioner] In `terraform/environments/dev/main.tf`: add `interpreter = ["/bin/bash", "-c"]` to the `local-exec` provisioner in `null_resource "apply_flannel_cni"` (the default `/bin/sh` is dash on the CI runner, which lacks `set -o pipefail`; the `command` heredoc is unchanged)

---

## Stage 2: Verification (CI-only — executed in GitHub Actions, never locally)

- [ ] T002 [Stage 2: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T001)
- [ ] T003 [Stage 2: Verify] AC-002: `interpreter` argument present on the local-exec provisioner (`grep -q 'interpreter = \["/bin/bash", "-c"\]' terraform/environments/dev/main.tf`) (Depends on T002)
- [ ] T004 [Stage 2: Verify] AC-003: `set -euo pipefail` still present in the provisioner command (`grep -q 'set -euo pipefail' terraform/environments/dev/main.tf`) (Depends on T003)
- [ ] T005 [Stage 2: Verify] AC-004: Terraform plan generates expected resource delta without errors (`terraform plan -detailed-exitcode`) (Depends on T004)
- [ ] T006 [Stage 2: Verify] AC-005: Flannel CNI daemonset rolled out on the cluster (SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`) (Depends on T005)

---

## Dependencies / Execution Order

```
T001 ─ T002 ─ T003 ─ T004 ─ T005 ─ T006
```

- **Sequential**: T001 → T002 → T003 → T004 → T005 → T006 (edit → static checks → clean plan → daemonset rollout)
- **Ordering constraint**: T005 (clean plan) confirms the provisioner config is valid; T006 (daemonset rollout) is the end-to-end proof the SSM command ran to completion

## Notes

- **1:1 file mapping**: T001 touches exactly one file (constitution DAG principle) — the `local-exec` provisioner in `null_resource "apply_flannel_cni"`
- **No Terraform resource changes**: provisioner-interpreter-only correction — the null resource re-runs (SSM command re-issued), no instance replacement, no state drift
- **Deployment**: applied by the existing `.github/workflows/terraform-apply.yml` on main push — no local apply (constitution principles 5, 6, 8)
- **Verification**: Stage 2 tasks run in GitHub Actions CI only — never locally
