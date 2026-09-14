# Technical Quality Checklist: CCM CreateSecurityGroup IAM Action

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-14
**Feature**: `004-7-ccm-create-security-group`

## Infrastructure Contracts
- [x] CHK001: Single-file change — `modules/cluster-plumbing/main.tf` (`node_aws_ccm` Action list only); no new resource, no manifest, no CCM arg, no tag change
- [x] CHK002: Adds `ec2:CreateSecurityGroup` (the immediate 403) + `ec2:AuthorizeSecurityGroupIngress` + `ec2:RevokeSecurityGroupIngress` (the next steps in the same EnsureLoadBalancer flow)
- [x] CHK003: `ec2:DeleteSecurityGroup` already present (line 201) — not duplicated
- [x] CHK004: `Resource = "*"` unchanged (matches the existing policy; the CCM creates the SG in the cluster VPC)
- [x] CHK005: CCM `--v=4` (004-5) + instance cluster tag (004-6) stay

## Root Cause Coverage
- [x] CHK006: CCM `--v=4` log confirms the exact failing action: `ec2:CreateSecurityGroup` on `vpc/vpc-00004ff9a1efc205c` (403 UnauthorizedOperation)
- [x] CHK007: The 004-4 policy has `ec2:DeleteSecurityGroup` but not `ec2:CreateSecurityGroup` — the gap is confirmed in the source (line 201)
- [x] CHK008: Adding the full SG lifecycle (Create + Authorize + Revoke) avoids a second spec cycle for the next 403 (AuthorizeSecurityGroupIngress)

## Terraform / Apply
- [x] CHK009: IAM policy update is in-place (no role replacement, no instance profile change) — `aws_iam_role_policy` is updatable
- [x] CHK010: Plan delta is exactly the `node_aws_ccm` policy update (AC-002) — no collateral changes
- [x] CHK011: No `null_resource` re-run needed — the CCM is already Running and re-syncs the LoadBalancer Service on its own (the `SyncLoadBalancerFailed` event will clear on the next sync after the policy propagates)

## Acceptance Criteria
- [x] CHK012: All 6 ACs machine-verifiable (terraform fmt/validate/plan + kubectl logs/get)
- [x] CHK013: AC-003 greps the plan for the new actions (proves the policy change is live)
- [x] CHK014: AC-004 confirms no new `SyncLoadBalancerFailed` (the root-cause fix)
- [x] CHK015: AC-005/AC-006 confirm the ELB is created + Ingress ADDRESS populated (004-4's blocked ACs)

## Scope Discipline
- [x] CHK016: No CCM version change, no CCM arg change, no instance tag change
- [x] CHK017: No Route53 / TLS (deferred)
- [x] CHK018: No resource-scoping of the SG actions (kept `Resource = "*"`; least-privilege scoping is a separate concern)
