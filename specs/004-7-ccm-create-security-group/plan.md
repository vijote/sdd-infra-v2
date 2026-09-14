# Architecture Delta: CCM CreateSecurityGroup IAM Action

**Branch**: `004-7-ccm-create-security-group` | **Date**: 2026-09-14 | **Spec**: [specs/004-7-ccm-create-security-group/spec.md](spec.md)

## 1. File Impact Matrix

| File | Operation | Description |
|------|-----------|-------------|
| `terraform/modules/cluster-plumbing/main.tf` | Modify | In `aws_iam_role_policy.node_aws_ccm` `Action` list (line ~199–204, EC2 section): add `ec2:CreateSecurityGroup`, `ec2:AuthorizeSecurityGroupIngress`, `ec2:RevokeSecurityGroupIngress` alongside the existing `ec2:DeleteSecurityGroup` (line 201). |

Single-file change. No new resource, no manifest, no CCM arg, no tag change.

## 2. Key Design Decisions

### 2.1 Why the full SG lifecycle, not just `CreateSecurityGroup`
The CCM's `EnsureLoadBalancer` flow for the ingress-nginx Service is:
1. **Create** the LB's security group ← current 403
2. **Authorize** ingress rules (ports 80/443 from the node CIDR) ← next 403 if only step 1 is fixed
3. Create the LB (ELB API — already granted)
4. Create target group + listener + register targets (already granted)
5. On re-sync: **Revoke/Authorize** rule changes

Adding only `ec2:CreateSecurityGroup` would trade one spec cycle for another (the CCM would 403 on `AuthorizeSecurityGroupIngress` seconds later). Adding the complete SG lifecycle in one change closes the whole gap. `ec2:DeleteSecurityGroup` is already present (004-4, line 201) — not duplicated.

### 2.2 Why `Resource = "*"` (unchanged)
The existing `node_aws_ccm` policy uses `Resource = "*"` for all actions (mirrors `node_ebs_csi`). The SG the CCM creates is in the cluster VPC, but scoping `ec2:CreateSecurityGroup` to a specific VPC ARN is possible yet inconsistent with the rest of the policy; least-privilege scoping is a separate concern (out of scope per spec §4).

### 2.3 In-place update, no re-run of any `null_resource`
- `aws_iam_role_policy` is **updatable** — Terraform does an in-place `iam:PutRolePolicy` (no role replacement, no instance profile change, no instance reboot).
- The CCM is **already Running** (004-6 fixed its init). It re-syncs the LoadBalancer Service on its own controller loop (and on the `SyncLoadBalancerFailed` event). Once the new policy propagates (IAM propagation is seconds), the next sync succeeds — no `apply_aws_ccm` re-run, no pod restart needed.
- If the sync doesn't retry promptly, a manual `kubectl delete pod -n kube-system -l app=aws-cloud-controller-manager` forces an immediate re-sync (verification aid only, not a Terraform change).

### 2.4 What stays
- CCM `--v=4` (004-5) — stays (diagnostics).
- Instance cluster tag (004-6) — stays (ClusterID init).
- VPC tag (004-4) — stays (harmless).
- CCM version — unchanged (`v1.28.11-eks-1-28-64`).

## 3. Rollout Stages

1. **Terraform apply** — in-place `PutRolePolicy` on `sdd-k8s-platform-node-role` (adds 3 actions). No replacement.
2. **CCM re-sync** — natural (controller loop / failed-event retry) or manual pod delete. The CCM's `EnsureLoadBalancer` proceeds: Create SG → Authorize 80/443 → Create LB → TG → listener → register targets.
3. **ELB ready** — `ingress-nginx-controller` Service gets EXTERNAL-IP → `app-ingress` gets ADDRESS.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` — plan shows ONLY the `node_aws_ccm` policy update (AC-001/AC-002)
- **Policy Validation**: `terraform plan -no-color | grep -c 'ec2:CreateSecurityGroup'` returns `1` (AC-003)
- **CCM Validation**: `kubectl logs ... | grep -c 'SyncLoadBalancerFailed'` returns `0` after the update (AC-004)
- **ELB Validation**: `kubectl get svc` EXTERNAL-IP + `kubectl get ingress` ADDRESS populated (AC-005/AC-006)

## 5. Risks / Notes

- **No collateral plan changes**: the only config delta is the `Action` list of one inline policy; all other resources are untouched.
- **In-place, safe**: `PutRolePolicy` is non-disruptive (no role replacement, no instance impact).
- **Downstream unblock**: once the ELB exists, 004-4's AC-003/004 (EXTERNAL-IP, Ingress ADDRESS) become verifiable, and the end-to-end `curl -H "Host: app.local" http://<ELB-DNS>/` + `/api/` test (007's path routing) becomes possible.
- **If another 403 appears** (e.g. `elasticloadbalancing:CreateLoadBalancer` or `ec2:CreateTags` on the LB) → the `--v=4` logs will show the exact action; scope a follow-on spec (004-8) with the missing action. The ELB API actions (`elasticloadbalancing:*`) are already granted by 004-4, so this is unlikely.
