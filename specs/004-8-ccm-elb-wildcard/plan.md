# Architecture Delta: CCM ELB Wildcard IAM Action

**Branch**: `004-8-ccm-elb-wildcard` | **Date**: 2026-09-14 | **Spec**: [specs/004-8-ccm-elb-wildcard/spec.md](spec.md)

## 1. File Impact Matrix

| File | Operation | Change |
|------|-----------|--------|
| `terraform/modules/cluster-plumbing/main.tf` | Modify | In `aws_iam_role_policy.node_aws_ccm`, replace the 15 granular `elasticloadbalancing:*` actions (lines ~207–216) with a single `"elasticloadbalancing:*"` wildcard. EC2 + ASG sections unchanged. |

## 2. Architectural Boundaries & Dependency Flow

- **IAM Layer**: `aws_iam_role_policy.node_aws_ccm` (inline policy on `sdd-k8s-platform-node-role`) — the CCM pod uses the node's instance-profile credentials via IMDS (no IRSA).
- **Consumer**: `aws-cloud-controller-manager` Deployment (`kube-system`) — `EnsureLoadBalancer` for `ingress-nginx-controller` needs the full ELBv2 API surface.
- **No graph change**: the policy is attached to the existing node role; no new resource, no `depends_on` change, no manifest change.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` → in-place `PutRolePolicy` on `sdd-k8s-platform-node-role` (no role replacement, no node replacement).
2. **Stage 2 - CCM resync**: the CCM picks up the new permissions on its next `EnsureLoadBalancer` retry (exponential backoff) or on a pod restart. The ELB `af8bcb49517a643ebaa2ecdbb0a6a960` already exists — the CCM finishes the attribute sync and populates the Service EXTERNAL-IP.
3. **Stage 3 - Ingress**: the ingress-nginx controller publishes the ELB DNS to the Ingress `ADDRESS`.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate`
- **Plan Delta**: `terraform plan -detailed-exitcode` → exit 2, exactly 1 `aws_iam_role_policy.node_aws_ccm` in-place update
- **Policy Content**: `terraform plan -no-color | grep -c 'elasticloadbalancing:\*'` → `1`
- **CCM Health**: `kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 | grep -c 'SyncLoadBalancerFailed'` → `0`
- **Service Endpoint**: `kubectl get svc -n ingress-nginx ingress-nginx-controller` → EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com`
- **Ingress Address**: `kubectl get ingress -n sdd-apps app-ingress` → ADDRESS = ELB DNS

## 5. Key Decisions

- **Wildcard over granular**: the CCM's `EnsureLoadBalancer` needs the full ELBv2 API surface (attributes, rules, target health, listeners, account limits, services). The granular list is proven incomplete (2 missing actions across 004-4/004-7). A wildcard ends the whack-a-mole in one change and matches the existing project decision (wildcard `iam:*` on the deploy role, dev-only education project).
- **EC2/ASG unchanged**: 004-7's SG lifecycle actions (`CreateSecurityGroup`, `AuthorizeSecurityGroupIngress`, `RevokeSecurityGroupIngress`) stay — they're correct and complete for the EC2 side.
- **No CCM restart required**: the policy update is picked up on the CCM's next retry; a `kubectl delete pod` is a fallback if the backoff is slow.
