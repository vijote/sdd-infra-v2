# Spec: Worker Output Splat Fix

**Feature Branch**: `003-0-worker-output-splat-fix` | **Date**: 2026-09-06 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform output expression correction only — no new AWS resources, no resource changes
- **Kubernetes / Cluster Scope**: Worker nodes module (003-3-worker-nodes)
- **Target Service**: `terraform/modules/worker-nodes/outputs.tf` (root output `worker_instance_ids`)
- **Root Cause (fatal)**: `terraform plan`/`apply` fails with `Error: Unsupported attribute ... This object does not have an attribute named "id"`. The `aws_instance.worker` resource is declared with `for_each` (a **map** keyed by `worker-0`/`worker-1`), so the list splat `aws_instance.worker[*].id` does not resolve — the `[*]` index operator is only valid on **lists** (i.e. `count`-based resources). On a map it yields an object with no `.id` attribute.
- **Decision**: Replace the list splat with a `for` expression over the map: `sort([for _, inst in aws_instance.worker : inst.id])`. This iterates the map values (each an `aws_instance` object) and collects `.id`, then sorts for deterministic output.

### 1.1 Terraform Output Contract

File: `terraform/modules/worker-nodes/outputs.tf`

**Before (broken — list splat on a `for_each` map):**

```hcl
output "worker_instance_ids" {
  value       = sort([for id in aws_instance.worker[*].id : id])
  description = "Worker EC2 instance IDs (consumed by 003-3 verification AC-003)"
}
```

**After (fixed — `for` expression over the map):**

```hcl
output "worker_instance_ids" {
  value       = sort([for _, inst in aws_instance.worker : inst.id])
  description = "Worker EC2 instance IDs (consumed by 003-3 verification AC-003)"
}
```

- **Why `for_each` is a map**: `main.tf` declares `resource "aws_instance" "worker" { for_each = local.worker_subnets }` where `local.worker_subnets` is a map (`worker-0`, `worker-1`). A `for_each` resource is therefore a **map** of objects, not a list.
- **Contrast (no change needed)**: `terraform/modules/vpc/outputs.tf` uses `aws_subnet.public[*].id` / `aws_subnet.private[*].id` — those resources are `count`-based (a **list**), so the `[*]` splat is valid there. Only the `for_each`-based worker output required the fix.
- **No other changes**: `main.tf`, `variables.tf`, `versions.tf`, `bootstrap.sh` are unchanged. The output name and description are preserved so the 003-3 AC-003 verification command (`terraform output -raw worker_instance_ids`) is unaffected.

### 1.2 Deployment Contract

- **Method**: Existing `.github/workflows/terraform-apply.yml` on main push — no new workflow, no local apply (constitution principles 5, 6, 8)
- **Effect**: Output-only change; no resource replacement. `terraform plan` must now succeed where it previously errored, and `worker_instance_ids` resolves to the two worker instance IDs
- **Rollback**: Revert the `outputs.tf` expression and re-apply (output-only, no resource impact)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Broken list splat removed (`! grep -q 'aws_instance.worker\[\*\].id' terraform/modules/worker-nodes/outputs.tf`)
- [ ] AC-003: Fixed `for` expression present (`grep -q 'for _, inst in aws_instance.worker : inst.id' terraform/modules/worker-nodes/outputs.tf`)
- [ ] AC-004: Terraform plan generates expected resource delta without errors (`terraform plan -detailed-exitcode`)
- [ ] AC-005: `worker_instance_ids` output resolves to 2 instance IDs (`terraform output -raw worker_instance_ids | tr -d '[]"' | tr ',' ' ' | wc -w | grep -q '^2$'`)

## 3. Assumptions & Constraints

- **Scope**: Output-expression-only correction; no change to instance count, type, subnet, IAM, or bootstrap
- **Map vs list rule**: `for_each` resources are maps (use `for` expressions); `count` resources are lists (use `[*]` splat). This is the general Terraform idiom the fix relies on
- **Determinism**: `sort()` keeps the output order stable across plans, so downstream consumers (003-3 AC-003) see a consistent list
- **Ordering**: This spec MUST be applied before 003-3's worker nodes are considered deployable; AC-004 (clean plan) is the end-to-end proof the expression resolves
