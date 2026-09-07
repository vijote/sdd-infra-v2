# Execution Graph (DAG): Flannel SSM Params JSON Fix

**Input**: Design documents from `/specs/003-6-flannel-ssm-params-json-fix/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~2 min (agent file edit) + CI verification

---

## Stage 1: Command Escaping Correction

- [x] T001 [Stage 1: Command] In `terraform/environments/dev/main.tf`: in the `local-exec` provisioner's `command` heredoc for `null_resource "apply_flannel_cni"`, reduce the four `\\\"` (triple-backslash + quote) escapes in the `--parameters` argument to `\"` (single-backslash + quote) so the AWS CLI receives valid JSON `commands=["curl ...","kubectl ..."]` (the `interpreter` line, SSM flags, and poll loop are unchanged)

---

## Stage 2: Verification (CI-only — executed in GitHub Actions, never locally)

- [ ] T002 [Stage 2: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T001)
- [ ] T003 [Stage 2: Verify] AC-002: `--parameters` uses single-backslash JSON quotes (`grep -qF 'commands=[\"' terraform/environments/dev/main.tf`) (Depends on T002)
- [ ] T004 [Stage 2: Verify] AC-003: Triple-backslash over-escape removed (`! grep -qF '\\\"' terraform/environments/dev/main.tf`) (Depends on T003)
- [ ] T005 [Stage 2: Verify] AC-004: Terraform plan generates expected resource delta without errors (`terraform plan -detailed-exitcode`) (Depends on T004)
- [ ] T006 [Stage 2: Verify] AC-005: Flannel CNI daemonset rolled out on the cluster (SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`) (Depends on T005)

---

## Dependencies / Execution Order

```
T001 ─ T002 ─ T003 ─ T004 ─ T005 ─ T006
```

- **Sequential**: T001 → T002 → T003 → T004 → T005 → T006 (edit → static checks → clean plan → daemonset rollout)
- **Ordering constraint**: T005 (clean plan) confirms the provisioner config is valid; T006 (daemonset rollout) is the end-to-end proof the SSM command was accepted (valid JSON) and ran to completion

## Notes

- **1:1 file mapping**: T001 touches exactly one file (constitution DAG principle) — the `--parameters` argument in the `local-exec` provisioner
- **No Terraform resource changes**: command-escaping-only correction — the null resource re-runs (SSM command re-issued), no instance replacement, no state drift
- **Deployment**: applied by the existing `.github/workflows/terraform-apply.yml` on main push — no local apply (constitution principles 5, 6, 8)
- **Verification**: Stage 2 tasks run in GitHub Actions CI only — never locally
- **Escaping reference**: file `\"` → Terraform heredoc passes through → bash double-quote collapses `\"` → `"` → AWS CLI JSON `commands=["curl ...","kubectl ..."]` (valid)
