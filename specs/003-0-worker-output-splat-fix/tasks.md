# Execution Graph (DAG): Worker Output Splat Fix

**Input**: Design documents from `/specs/003-0-worker-output-splat-fix/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~2 min (agent file edit) + CI verification

---

## Stage 1: Output Expression Correction

- [x] T001 [Stage 1: Output] In `terraform/modules/worker-nodes/outputs.tf`: replace the broken list splat `sort([for id in aws_instance.worker[*].id : id])` with the map-safe `for` expression `sort([for _, inst in aws_instance.worker : inst.id])` for the `worker_instance_ids` output (the `aws_instance.worker` resource is `for_each`-based, i.e. a map, so `[*]` does not resolve)

---

## Stage 2: Verification (CI-only — executed in GitHub Actions, never locally)

- [ ] T002 [Stage 2: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T001)
- [ ] T003 [Stage 2: Verify] AC-002: Broken list splat removed (`! grep -q 'aws_instance.worker\[\*\].id' terraform/modules/worker-nodes/outputs.tf`) (Depends on T002)
- [ ] T004 [Stage 2: Verify] AC-003: Fixed `for` expression present (`grep -q 'for _, inst in aws_instance.worker : inst.id' terraform/modules/worker-nodes/outputs.tf`) (Depends on T003)
- [ ] T005 [Stage 2: Verify] AC-004: Terraform plan generates expected resource delta without errors (`terraform plan -detailed-exitcode`) (Depends on T004)
- [ ] T006 [Stage 2: Verify] AC-005: `worker_instance_ids` output resolves to 2 instance IDs (`terraform output -raw worker_instance_ids | tr -d '[]"' | tr ',' ' ' | wc -w | grep -q '^2$'`) (Depends on T005)

---

## Dependencies / Execution Order

```
T001 ─ T002 ─ T003 ─ T004 ─ T005 ─ T006
```

- **Sequential**: T001 → T002 → T003 → T004 → T005 → T006 (edit → static checks → clean plan → output resolution)
- **Ordering constraint**: T005 (clean plan) is the end-to-end proof the expression resolves; T006 confirms the output yields exactly 2 worker instance IDs

## Notes

- **1:1 file mapping**: T001 touches exactly one file (constitution DAG principle) — the `worker_instance_ids` output expression
- **No Terraform resource changes**: output-only correction — no instance replacement, no state drift
- **Deployment**: applied by the existing `.github/workflows/terraform-apply.yml` on main push — no local apply (constitution principles 5, 6, 8)
- **Verification**: Stage 2 tasks run in GitHub Actions CI only — never locally
- **Status**: T001 already applied and pushed (`a7836de`); Stage 2 pending CI run
