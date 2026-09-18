# Architecture Delta: node_route53 Wildcard + Re-apply Trigger

**Branch**: `009-1-node-route53-wildcard` | **Date**: 2026-09-17 | **Spec**: [specs/009-1-node-route53-wildcard/spec.md]

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/modules/cluster-plumbing/main.tf` | Modify | `aws_iam_role_policy.node_route53` — action list → `["route53:*"]` (covers the missing `route53:ListHostedZones`) |
| `terraform/environments/dev/main.tf` | Modify | `null_resource.apply_route53_record` — add `route53_ref = "route53-wildcard"` trigger so the SSM command re-runs after the IAM change |

No manifest, variable, or script edits. `scripts/create-route53-record.sh` is unchanged (its `list-hosted-zones` call is correct; the policy was missing the action).

### 1.1 Exact Edits

**Edit A** — `terraform/modules/cluster-plumbing/main.tf`, `aws_iam_role_policy.node_route53` (~line 224):
```hcl
# BEFORE:
      Action = [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:GetHostedZone"
      ]
# AFTER:
      Action   = ["route53:*"]
```
`Resource = "*"` unchanged. Update the `# Inline policy:` comment block above the resource to note 009-1's wildcard (004-8 precedent).

**Edit B** — `terraform/environments/dev/main.tf`, `null_resource.apply_route53_record` (~line 744):
```hcl
# BEFORE:
  triggers = {
    domain      = var.ingress_host
    instance_id = module.control_plane.control_plane_instance_id # 004-10: re-apply on cluster recreation
  }
# AFTER:
  triggers = {
    domain      = var.ingress_host
    instance_id = module.control_plane.control_plane_instance_id # 004-10: re-apply on cluster recreation
    route53_ref = "route53-wildcard" # 009-1: re-run SSM command after node_route53 wildcard (domain/instance_id unchanged by an IAM edit)
  }
```
The `depends_on` already includes `module.cluster_plumbing`, so the policy update is applied before the SSM command runs — no dependency change needed.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: the only touched boundary — one IAM role policy on the node role (shared by control plane + workers).
- **Cluster Control Plane & Core Addons**: unchanged.
- **Platform Services**: unchanged (cert-manager, ingress-nginx).
- **Application Workloads**: unchanged.
- **Dependency Flow (unchanged)**: `apply_aws_ccm` + `module.cluster_plumbing` → `apply_route53_record` → (downstream) `apply_app_frontend_ingress` is NOT a consumer of `apply_route53_record` (009 deliberately avoided that edge to prevent a cycle). The SSM script's three steps are unchanged: (1) poll ALB DNS, (2) `list-hosted-zones` zone lookup (now authorized), (3) `change-resource-record-set` UPSERT.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` — `aws_iam_role_policy.node_route53` updates in place (policy document change on the existing role; no role/profile recreation, no instance interruption); `null_resource.apply_route53_record` is replaced (trigger change); all other resources are no-ops.
2. **Stage 2 - SSM Re-apply (in-place repair)**: the provisioner re-runs on the EXISTING control plane: SSM-agent wait → bootstrap-instance-id gate → `create-route53-record.sh`. Step (2) `list-hosted-zones` now succeeds (wildcard policy); step (3) UPSERTs the ALIAS record (idempotent — a no-op if a prior run already created it).
3. **Stage 3 - Downstream (unchanged)**: 009's AC-004–AC-006 (certificate issuance, HTTPS curl) become reachable once the record is live; cert-manager retries HTTP-01 automatically.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (plan shows ONLY the `node_route53` policy update + `apply_route53_record` replacement).
- **Zone Lookup (the previously-403'd call)**: via SSM on the control plane — `aws route53 list-hosted-zones --query "HostedZones[?Name=='vijote.dev.'].Id" --output text` → a zone ID, no `AccessDenied`.
- **ALIAS Record**: `aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID> --query "ResourceRecordSets[?Name=='demo.vijote.dev.'].AliasTarget.DNSName" --output text` → the ALB DNS name.
- **SSM Invocation**: `aws ssm get-command-invocation --instance-id <cp> --command-id <cmd> --query 'CommandInvocation.Status' --output text` → `Success` (no `AccessDenied` in StdErr).
