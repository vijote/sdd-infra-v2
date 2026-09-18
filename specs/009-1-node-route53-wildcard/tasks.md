# Execution Graph (DAG): node_route53 Wildcard + Re-apply Trigger

**Input**: Design documents from `/specs/009-1-node-route53-wildcard/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 2 implementation tasks (parallel) + 3 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: IAM] In `terraform/modules/cluster-plumbing/main.tf`, resource `aws_iam_role_policy.node_route53` (009): replace the `Action` list (`route53:ChangeResourceRecordSets`, `route53:ListResourceRecordSets`, `route53:GetHostedZone`) with `Action = ["route53:*"]` (004-8 wildcard precedent — the granular list was structurally incomplete: the SSM script's `aws route53 list-hosted-zones` zone lookup needs `route53:ListHostedZones`, which was missing → AccessDenied). Keep `Resource = "*"`. Update the `# Inline policy:` comment block above the resource to note 009-1's wildcard. Do NOT touch: `name`, `role`, or any other resource in the module
- [x] T002 [Stage 1: Terraform] In `terraform/environments/dev/main.tf`, resource `null_resource.apply_route53_record` (009): add a third trigger `route53_ref = "route53-wildcard"` (with a `# 009-1` comment explaining that an IAM edit does not change `domain`/`instance_id` and the command string is not in `null_resource` state, so the bump forces the SSM command re-run). Do NOT touch: `depends_on` (already includes `module.cluster_plumbing`), the provisioner command, or `scripts/create-route53-record.sh`

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T003 [Stage 2: Verify] AC-001/AC-002 static: `terraform fmt -check -recursive` + `terraform validate` + `terraform plan -detailed-exitcode` — plan must show ONLY `aws_iam_role_policy.node_route53` update + `null_resource.apply_route53_record` replacement (trigger change); zero changes to other resources
- [ ] T004 [Stage 2: Verify] AC-003/AC-004: via SSM on the control plane — (1) `aws route53 list-hosted-zones --query "HostedZones[?Name=='vijote.dev.'].Id" --output text` returns a zone ID with no `AccessDenied` (the previously-403'd call), (2) `aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID> --query "ResourceRecordSets[?Name=='demo.vijote.dev.'].AliasTarget.DNSName" --output text` returns the ALB DNS name
- [ ] T005 [Stage 2: Verify] AC-005: the `apply_route53_record` SSM invocation `Status == Success` with no `AccessDenied` in StdErr (via SSM: `aws ssm get-command-invocation --command-id <CID> --instance-id <IID> --query 'CommandInvocation.Status' --output text`)
