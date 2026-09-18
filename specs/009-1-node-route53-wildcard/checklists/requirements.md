# Requirements Checklist: node_route53 Wildcard + Re-apply Trigger

## Technical Contracts Declared
- [x] Terraform HCL contract: `aws_iam_role_policy.node_route53` action list → `["route53:*"]` (exact before/after)
- [x] Terraform HCL contract: `null_resource.apply_route53_record` new `route53_ref` trigger (exact HCL)
- [x] Kubernetes manifest contract: none (no manifest change)
- [x] Data & storage: none
- [x] Network & security: IAM boundary change documented (3 actions → `route53:*`, `Resource = "*"` unchanged, dev-only, prod scoping deferred)

## Machine-Verifiable Acceptance Criteria
- [x] AC-001: `terraform fmt -check -recursive && terraform validate`
- [x] AC-002: `terraform plan -detailed-exitcode` — policy update + `apply_route53_record` replacement only
- [x] AC-003: `aws route53 list-hosted-zones` via SSM returns the `vijote.dev` zone ID (no AccessDenied)
- [x] AC-004: ALIAS record present pointing at the ALB (009 AC-003, now reachable)
- [x] AC-005: `apply_route53_record` SSM invocation `Status == Success`

## Security, IAM & Network Boundaries
- [x] Wildcard justified by 004-8 precedent + existing node-role wildcard policies + `Resource` already `*`
- [x] Prod tightening (scope to zone ID) explicitly deferred, matching 009 spec
- [x] No new SG rules / IRSA change

## Zero Narrative / Token Efficiency
- [x] No conversational filler or marketing language
- [x] Spec < 200 lines (81 lines)
- [x] Root cause stated as a technical fact (missing `route53:ListHostedZones` action), not narrative

## SpecKit Constraints
- [x] Follow-on numbering: `009-1` (next sequential in the 009 series — the spec that owns `node_route53`)
- [x] Trigger bump documented (command string not in `null_resource` state; `domain`/`instance_id` unchanged by an IAM edit)
- [x] Testing policy: no test generation; AC-003–AC-005 user-managed SSM/CLI checks
