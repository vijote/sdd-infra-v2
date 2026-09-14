# Technical Quality Checklist: CCM ELB Wildcard IAM Action

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-14
**Feature**: `004-8-ccm-elb-wildcard`

## Infrastructure Contracts
- [x] CHK001: Target resource identified (`aws_iam_role_policy.node_aws_ccm` in `modules/cluster-plumbing/main.tf`)
- [x] CHK002: Change is a single action-list edit (granular ELB list → `elasticloadbalancing:*`), no new resource
- [x] CHK003: EC2 + ASG sections explicitly unchanged (004-7's SG lifecycle preserved)
- [x] CHK004: `Resource = "*"` scope unchanged (matches existing policy)
- [x] CHK005: No manifest / CCM arg / instance tag / VPC change

## Security & IAM
- [x] CHK006: Wildcard justified (dev-only education project; matches existing wildcard `iam:*` deploy-role decision)
- [x] CHK007: Granular list proven incomplete (2 missing actions across 004-4/004-7; more likely remain)
- [x] CHK008: No secret/credential exposure (policy is static HCL, no values)

## Machine-Verifiability
- [x] CHK009: AC-001 `terraform fmt -check -recursive && terraform validate` — exit 0
- [x] CHK010: AC-002 `terraform plan -detailed-exitcode` — exit 2, exactly 1 in-place policy update
- [x] CHK011: AC-003 `terraform plan | grep -c 'elasticloadbalancing:\*'` — `1`
- [x] CHK012: AC-004 CCM logs `grep -c 'SyncLoadBalancerFailed'` — `0`
- [x] CHK013: AC-005 Service EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com`
- [x] CHK014: AC-006 Ingress ADDRESS = ELB DNS

## Scope & Downstream
- [x] CHK015: Out-of-scope list explicit (no CCM version/arg/tag/EC2 change, no Route53/TLS)
- [x] CHK016: Downstream consumer identified (004-4 AC-003/004, 008 end-to-end curl)
- [x] CHK017: Spec < 200 lines
- [x] CHK018: Zero narrative (technical content only)
