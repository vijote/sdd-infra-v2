---
name: 004-7-ccm-create-security-group
description: Add the full EC2 security group lifecycle actions (Create/Authorize/Revoke) to the node CCM policy so the CCM can create and configure the ELB's security group.
date: 2026-09-14
status: Implemented
---

# Spec: CCM CreateSecurityGroup IAM Action

**Feature Branch**: `004-7-ccm-create-security-group` | **Date**: 2026-09-14 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: IAM only (one inline policy action list)
- **Kubernetes / Cluster Scope**: `aws-cloud-controller-manager` (`kube-system`) — unblocks ELB creation
- **Target Services / Modules**: `terraform/modules/cluster-plumbing/main.tf` — `aws_iam_role_policy.node_aws_ccm`
- **Root Cause (confirmed via CCM `--v=4` logs, 004-5)**: After 004-6 fixed the ClusterID tag, the CCM started cleanly (`1/1 Running`, 0 restarts) and began `EnsureLoadBalancer` for `ingress-nginx-controller`. It then failed:
  ```
  SyncLoadBalancerFailed: failed to ensure load balancer:
  UnauthorizedOperation: ... not authorized to perform: ec2:CreateSecurityGroup
  on resource: arn:aws:ec2:us-east-1:891377205721:vpc/vpc-00004ff9a1efc205c
  ```
  The `node_aws_ccm` policy (004-4) grants `ec2:DeleteSecurityGroup` (line 201) but **not** `ec2:CreateSecurityGroup`. The CCM creates a security group for the ELB as the first step of `EnsureLoadBalancer`.

## 2. Infrastructure Contracts

### 2.1 Node CCM Policy (Modify — `modules/cluster-plumbing/main.tf`)
- **Target**: `aws_iam_role_policy.node_aws_ccm` `Action` list (line ~199–204, the EC2 section)
- **Change**: add the **complete SG lifecycle** the CCM needs for the ELB's security group:
  - `ec2:CreateSecurityGroup` (the immediate failure)
  - `ec2:AuthorizeSecurityGroupIngress` (next step — opens ports 80/443 on the LB SG)
  - `ec2:RevokeSecurityGroupIngress` (SG rule updates on LB re-sync)
  - (`ec2:DeleteSecurityGroup` is already present, line 201)
- **Why all three, not just Create**: the CCM's `EnsureLoadBalancer` flow is Create SG → Authorize ingress (80/443) → Create LB → Create TG → Create listener → Register targets. Adding only `CreateSecurityGroup` would make the CCM fail on `AuthorizeSecurityGroupIngress` next, requiring another full spec cycle. Adding the full SG lifecycle in one change avoids the whack-a-mole.
- **Resource scope**: `Resource = "*"` (unchanged — matches the existing policy; the CCM creates the SG in the cluster VPC and the action is not resource-scoped in the current policy).

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

- [ ] AC-003: Policy contains the SG lifecycle actions
  ```
  terraform plan -no-color | grep -c 'ec2:CreateSecurityGroup'
  ```
  **Expected**: `1` (and `ec2:AuthorizeSecurityGroupIngress` + `ec2:RevokeSecurityGroupIngress` also present)

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
- No Route53 / TLS (deferred)
- No resource-scoping of the SG actions (kept `Resource = "*"` to match the existing policy; least-privilege scoping is a separate concern)

## 5. Downstream Consumer
- **004-4-aws-cloud-controller-manager** — AC-003/004 (EXTERNAL-IP, Ingress ADDRESS) become verifiable once the ELB is created
- **008 (ECR + real apps)** — Ingress path routing (`/api` → backend) is live on the ELB; end-to-end `curl -H "Host: app.local" http://<ELB-DNS>/` + `/api/` test becomes possible
