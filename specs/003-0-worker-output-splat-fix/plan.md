# Architecture Delta: Worker Output Splat Fix

**Branch**: `003-0-worker-output-splat-fix` | **Date**: 2026-09-06 | **Spec**: specs/003-0-worker-output-splat-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/modules/worker-nodes/outputs.tf` | Modify | Replace the broken list splat `sort([for id in aws_instance.worker[*].id : id])` with the map-safe `for` expression `sort([for _, inst in aws_instance.worker : inst.id])` for the `worker_instance_ids` output |

**No other files change.** `main.tf`, `variables.tf`, `versions.tf`, `bootstrap.sh`, the dev environment, workflows, and all other modules are untouched — this is an output-expression-only correction.

## 2. Architectural Boundaries & Dependency Flow

- **Boundary**: The fix lives in the Terraform output layer of the worker-nodes module (003-3) — no resource change, no CloudFormation, no IAM change, no bootstrap change
- **Root cause (fatal)**: `aws_instance.worker` is declared with `for_each` (a **map** keyed `worker-0`/`worker-1`), so the list splat `aws_instance.worker[*].id` does not resolve — `[*]` is only valid on **lists** (`count`-based resources). On a map it yields an object with no `.id` attribute, so `terraform plan`/`apply` aborts with `Error: Unsupported attribute`
- **Fix flow**: `for` expression iterates the map values (each an `aws_instance` object) → collects `.id` → `sort()` yields a deterministic 2-element list → `worker_instance_ids` resolves
- **Consumers**:
  - 003-3 AC-003 verification → `terraform output -raw worker_instance_ids` (2 worker instance IDs)
  - Downstream 003-3 wiring (`null_resource "apply_flannel_cni"`) depends on `module.worker_nodes`, not the output directly
- **No resource replacement**: output-only change; the two worker instances are untouched, no destroy/re-launch

## 3. Provisioning & Rollout Stages

- **Stage 1 — Output edit (agent)**: Apply the `for`-expression fix in `terraform/modules/worker-nodes/outputs.tf`
- **Stage 2 — Apply (CI)**: Push/merge triggers existing `.github/workflows/terraform-apply.yml`; `terraform plan` now succeeds where it previously errored, and `worker_instance_ids` resolves to the two worker instance IDs
- **Stage 3 — Unblocks 003-3**: the worker-nodes module is deployable; AC-004 (clean plan) is the end-to-end proof the expression resolves

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `! grep -q 'aws_instance.worker\[\*\].id' terraform/modules/worker-nodes/outputs.tf`
- **AC-003**: `grep -q 'for _, inst in aws_instance.worker : inst.id' terraform/modules/worker-nodes/outputs.tf`
- **AC-004**: `terraform plan -detailed-exitcode`
- **AC-005**: `terraform output -raw worker_instance_ids | tr -d '[]"' | tr ',' ' ' | wc -w | grep -q '^2$'`

## 5. Risks & Mitigations

- **Map vs list rule**: `for_each` resources are maps (use `for` expressions); `count` resources are lists (use `[*]` splat). The fix relies on this general Terraform idiom
- **VPC splat confirmed valid**: `terraform/modules/vpc/outputs.tf` uses `aws_subnet.public[*].id` / `aws_subnet.private[*].id` on `count`-based (list) resources — left unchanged, no latent bug
- **Determinism**: `sort()` keeps the output order stable across plans, so downstream consumers see a consistent list
- **No resource impact**: output-only change; no instance replacement, no state drift
- **Rollback**: revert the `outputs.tf` expression and re-apply (output-only, no resource impact)
