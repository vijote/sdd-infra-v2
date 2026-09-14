# Spec: CCM ELB Wildcard IAM Action

**Feature Branch**: `004-8-ccm-elb-wildcard` | **Date**: 2026-09-14 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: IAM only (one inline policy action list)
- **Kubernetes / Cluster Scope**: `aws-cloud-controller-manager` (`kube-system`) — completes ELB lifecycle
- **Target Services / Modules**: `terraform/modules/cluster-plumbing/main.tf` — `aws_iam_role_policy.node_aws_ccm`
- **Root Cause (confirmed via CCM logs, post-004-7)**: After 004-7 added the EC2 SG lifecycle actions, the CCM started cleanly (`1/1 Running`), created the ELB (`af8bcb49517a643ebaa2ecdbb0a6a960`), then failed on the next missing action:
  ```
  SyncLoadBalancerFailed: failed to ensure load balancer: AccessDenied:
  ... not authorized to perform: elasticloadbalancing:DescribeLoadBalancerAttributes
  ```
  The `node_aws_ccm` policy (004-4) grants a **granular** `elasticloadbalancing:*` action list that is incomplete. Each missing action surfaces as a separate 403 on the next `EnsureLoadBalancer` retry, requiring a separate spec cycle per action (004-4 → 004-7 → this).

## 2. Infrastructure Contracts

### 2.1 Node CCM Policy (Modify — `modules/cluster-plumbing/main.tf`)
- **Target**: `aws_iam_role_policy.node_aws_ccm` `Action` list (line ~207–216, the ELB section)
- **Change**: replace the 15 granular `elasticloadbalancing:*` actions with a single wildcard:
  - `elasticloadbalancing:*`
- **Why wildcard, not more granular actions**: the CCM's `EnsureLoadBalancer` flow needs the full ELBv2 API surface (attributes, rules, target health, listeners, account limits, services). The granular list is already proven incomplete (2 missing actions found across 004-4/004-7, more likely remain). A wildcard ends the whack-a-mole in one change. This matches the existing project decision to use wildcard `iam:*` on the deploy role (dev-only education project, single environment).
- **EC2 + ASG sections unchanged**: the `ec2:*` and `autoscaling:DescribeAutoScalingGroups` actions stay as-is (004-7's SG lifecycle actions remain).
- **Resource scope**: `Resource = "*"` (unchanged — matches the existing policy).

### 2.2 No Other Changes
- No new resource, no manifest, no CCM arg change, no instance tag change, no VPC change.
- The CCM `--v=4` flag (004-5) and instance cluster tag (004-6) **stay**.

## 3. Acceptance Criteria

- [ ] AC-001: Terraform syntax & formatting validation passes
  ```
  terraform fmt -check -recursive && terraform validate
  ```
  **Expected**: exit 0, no diff

- [ ] AC-002: Plan shows only the `node_aws_ccm` policy update
  ```
  terraform plan -detailed-exitcode
  ```
  **Expected**: exit 2; plan shows exactly 1 `aws_iam_role_policy.node_aws_ccm` in-place update, zero other changes

- [ ] AC-003: Policy contains the ELB wildcard
  ```
  terraform plan -no-color | grep -c 'elasticloadbalancing:\*'
  ```
  **Expected**: `1` (and the granular `elasticloadbalancing:CreateLoadBalancer` etc. no longer present)

- [ ] AC-004: CCM no longer reports `SyncLoadBalancerFailed`
  ```
  kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 | grep -c 'SyncLoadBalancerFailed'
  ```
  **Expected**: `0` (no new sync failures after the policy update)

- [ ] AC-005: Ingress Service EXTERNAL-IP populated (ELB created)
  ```
  kubectl get svc -n ingress-nginx ingress-nginx-controller
  ```
  **Expected**: EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com` (not `<pending>`)

- [ ] AC-006: Ingress ADDRESS populated
  ```
  kubectl get ingress -n sdd-apps app-ingress
  ```
  **Expected**: ADDRESS = ELB DNS name (not empty)

## 4. Out of Scope
- No CCM version change (stays on `v1.28.11-eks-1-28-64`)
- No CCM arg change (`--v=4` from 004-5 stays)
- No instance tag change (004-6 stays)
- No EC2/ASG action change (004-7's SG lifecycle stays)
- No Route53 / TLS (deferred)
- No resource-scoping of the ELB wildcard (kept `Resource = "*"` to match the existing policy; least-privilege scoping is a separate concern)

## 5. Downstream Consumer
- **004-4-aws-cloud-controller-manager** — AC-003/004 (EXTERNAL-IP, Ingress ADDRESS) become verifiable once the ELB is created
- **008 (ECR + real apps)** — Ingress path routing (`/api` → backend) is live on the ELB; end-to-end `curl -H "Host: app.local" http://<ELB-DNS>/` + `/api/` test becomes possible
