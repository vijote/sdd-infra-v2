---
name: 009-1-node-route53-wildcard
description: Replace the incomplete granular route53 action list with a route53:* wildcard on the node role (the zone lookup needs ListHostedZones) and bump the apply trigger so the SSM command re-runs.
date: 2026-09-17
status: Implemented
---

# Spec: node_route53 Wildcard + Re-apply Trigger

**Feature Branch**: `009-1-node-route53-wildcard` | **Date**: 2026-09-17 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: 1 IAM role policy edit (`node_route53` in `module.cluster_plumbing`) + 1 trigger bump in the dev env
- **Kubernetes / Cluster Scope**: none (no manifest change)
- **Target Services / Modules**: `aws_iam_role_policy.node_route53` (added by 009) + `null_resource.apply_route53_record` (added by 009)
- **Security & CI/CD**: dev-only wildcard (004-8 precedent); no CI/CD change

> **Root cause (009)**: the `node_route53` policy enumerated three actions — `route53:ChangeResourceRecordSets`, `route53:ListResourceRecordSets`, `route53:GetHostedZone` — but the SSM script's zone lookup calls `aws route53 list-hosted-zones`, which requires **`route53:ListHostedZones`** (not in the list). The first Route 53 call in the script 403s → `AccessDenied ... not authorized to perform: route53:ListHostedZones` → script exits 254 → SSM `Failed`. There is no way to resolve a zone ID by name other than `list-hosted-zones` (`GetHostedZone` needs the ID you're trying to find), so the granular list is structurally incomplete. **Fix**: replace the three-action list with `route53:*` (004-8 precedent — the granular ELB list was replaced with `elasticloadbalancing:*` for the same reason; the node role already carries other wildcard policies; `Resource` is already `*`). A trigger bump on `apply_route53_record` is required because its triggers (`domain`, `instance_id`) do not change when the IAM policy updates, so the SSM command would otherwise not re-run.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# MODIFY aws_iam_role_policy.node_route53 (009) in terraform/modules/cluster-plumbing/main.tf:
resource "aws_iam_role_policy" "node_route53" {
  name = "sdd-k8s-platform-node-route53"
  role = aws_iam_role.node.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["route53:*"]   # was [ChangeResourceRecordSets, ListResourceRecordSets, GetHostedZone]
      Resource = "*"             # unchanged (dev-only; scope to the vijote.dev zone ID in prod)
    }]
  })
}

# MODIFY null_resource.apply_route53_record (009) in terraform/environments/dev/main.tf:
resource "null_resource" "apply_route53_record" {
  depends_on = [null_resource.apply_aws_ccm, module.cluster_plumbing]
  triggers = {
    domain      = var.ingress_host
    instance_id = module.control_plane.control_plane_instance_id
    # 009-1: bump so the SSM command re-runs after the IAM policy change (the command
    # string is NOT in null_resource state, and domain/instance_id are unchanged).
    route53_ref = "route53-wildcard"   # NEW trigger
  }
}
```

### 1.2 Kubernetes Manifest Contracts
- None (no manifest change).

### 1.3 Data & Storage Contracts
- None.

### 1.4 Network & Security Contracts
- **IAM boundary**: `node_route53` widens from 3 enumerated `route53` actions to `route53:*` on `Resource = "*"`. Dev-only (004-8 precedent); the prod tightening (scope to the `vijote.dev` zone ID) is deferred, as already noted in the 009 spec.
- No new SG rules, no IRSA change.

## 2. Technical Acceptance Criteria

AC-001/AC-002 static (existing `terraform-apply.yml` job). AC-003–AC-005 are **user-managed SSM/CLI checks** (P5/P6).

- [ ] AC-001: Terraform syntax & formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: `terraform plan -detailed-exitcode` — plan shows `aws_iam_role_policy.node_route53` update + `null_resource.apply_route53_record` replacement (trigger change); no unexpected diffs
- [ ] AC-003: the node role can list hosted zones (the previously-403'd call now succeeds)
  ```bash
  # via SSM on the control plane (node instance profile):
  aws route53 list-hosted-zones --query "HostedZones[?Name=='vijote.dev.'].Id" --output text   # → a zone ID (not empty, no AccessDenied)
  ```
- [ ] AC-004: the Route 53 ALIAS record is present, pointing at the ALB (the 009 AC-003, now reachable)
  ```bash
  aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID> --query "ResourceRecordSets[?Name=='demo.vijote.dev.'].AliasTarget.DNSName" --output text
  ```
- [ ] AC-005: the `apply_route53_record` SSM invocation returns `Success` (no `AccessDenied` in StdErr)
  ```bash
  # aws ssm get-command-invocation --instance-id <cp> --command-id <cmd> --query 'CommandInvocation.Status' --output text  # → Success
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependency**: `009-route53-domain` (adds `node_route53` + `apply_route53_record`). This spec widens the policy and forces the SSM command to re-run.
- **Trigger Bump Required**: the provisioner command string is NOT part of `null_resource` state (known gotcha), and `domain`/`instance_id` are unchanged by an IAM edit — the new `route53_ref` trigger forces the re-apply.
- **Wildcard Rationale**: 004-8 precedent (granular ELB list → `elasticloadbalancing:*`); the node role already carries wildcard policies; `Resource` is already `*`. Dev-only; prod scoping deferred.
- **Idempotency**: the SSM script uses `UPSERT`; the `null_resource` re-triggers on `domain`, `instance_id`, or `route53_ref` change.
- **Testing Policy**: No test generation (P6); AC-003–AC-005 are user-managed SSM/CLI checks, not added to workflows.
- **Tooling**: Terraform >= 1.5.0.
