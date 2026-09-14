# Technical Quality Checklist: CCM Instance Cluster Tag

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-13
**Feature**: `004-6-ccm-instance-cluster-tag`

## Infrastructure Contracts
- [x] CHK001: Two-file change — `modules/control-plane/main.tf` + `modules/worker-nodes/main.tf` (instance `tags` only); no new resource, no IAM, no manifest, no VPC change
- [x] CHK002: Tag key `kubernetes.io/cluster/sdd-k8s-platform` = `owned` (matches the VPC tag from 004-4 and the CCM `--cluster-name=sdd-k8s-platform` arg)
- [x] CHK003: Tag added to **both** the control plane and the workers (the CCM runs on a worker; the control plane is tagged for consistency)
- [x] CHK004: VPC tag from 004-4 stays (harmless; may be used by other tooling)
- [x] CHK005: CCM `--v=4` flag from 004-5 stays (useful for future diagnostics)

## Root Cause Coverage
- [x] CHK006: 004-5 `--v=4` trace confirms the CCM reads the cluster tag from the **instance's tags** (DescribeInstances called, then `tags.go:95` "tag not found", **no** DescribeSubnets/DescribeVpcs)
- [x] CHK007: The instance `i-0efe35678d39e688c` (the CCM's worker) does **not** have the cluster tag — only the VPC does
- [x] CHK008: Adding the tag to the instance resolves the `ClusterID()` init failure → CCM reaches Ready → ELB created

## Terraform / Apply
- [x] CHK009: Tag change is in-place (no instance replacement) — `tags` is an updatable attribute on `aws_instance`
- [x] CHK010: Plan delta is exactly the instance tag updates (AC-002) — no collateral changes
- [x] CHK011: No `null_resource` re-run needed (the CCM is already deployed; the tag change takes effect on the next CCM restart, which happens naturally as the pod crash-loops and restarts)

## Acceptance Criteria
- [x] CHK012: All 8 ACs machine-verifiable (terraform fmt/validate/plan + aws ec2 describe-instances + kubectl get/rollout)
- [x] CHK013: AC-003/AC-004 confirm the instance tag is present (the root-cause fix)
- [x] CHK014: AC-005/AC-006 confirm the CCM is Ready (the ultimate test)
- [x] CHK015: AC-007/AC-008 confirm the ELB is created + Ingress ADDRESS populated (004-4's blocked ACs)

## Scope Discipline
- [x] CHK016: No VPC tag change, no CCM version change, no CCM arg change
- [x] CHK017: No Route53 / TLS (deferred)
- [x] CHK018: No new `null_resource` (the CCM pod crash-loops and restarts naturally, picking up the new tag)
