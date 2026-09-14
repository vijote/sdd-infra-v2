# Execution Graph (DAG): CCM ELB Wildcard IAM Action

**Input**: Design documents from `/specs/004-8-ccm-elb-wildcard/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 1 implementation task + 5 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Terraform] In `terraform/modules/cluster-plumbing/main.tf`: in `aws_iam_role_policy.node_aws_ccm` `Action` list (ELB section, line ~207–216), replace the 15 granular `elasticloadbalancing:*` actions with a single `"elasticloadbalancing:*"` wildcard — the CCM's EnsureLoadBalancer flow 403'd on `elasticloadbalancing:DescribeLoadBalancerAttributes` after creating the ELB (post-004-7 log: `SyncLoadBalancerFailed ... AccessDenied ... DescribeLoadBalancerAttributes`); the granular list is proven incomplete, so the wildcard ends the whack-a-mole in one change (dev-only, matches the wildcard `iam:*` deploy-role decision); EC2 section (incl. 004-7's SG lifecycle) + `autoscaling:DescribeAutoScalingGroups` + `Resource = "*"` stay unchanged

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T002 [Stage 2: Verify] AC-001: `terraform fmt -check -recursive && terraform validate` — exit 0, no diff (Depends on T001)
- [ ] T003 [Stage 2: Verify] AC-002: `terraform plan -detailed-exitcode` — exit 2; plan shows exactly 1 `aws_iam_role_policy.node_aws_ccm` in-place update, zero other changes (Depends on T001)
- [ ] T004 [Stage 2: Verify] AC-003: `terraform plan -no-color | grep -c 'elasticloadbalancing:\*'` returns `1` (and the granular `elasticloadbalancing:CreateLoadBalancer` etc. no longer present) (Depends on T001)
- [ ] T005 [Stage 2: Verify] AC-004: after the next `terraform-apply` run — `kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 | grep -c 'SyncLoadBalancerFailed'` returns `0` (no new sync failures; force an immediate re-sync if needed: `kubectl delete pod -n kube-system -l app=aws-cloud-controller-manager`) (Depends on T001)
- [ ] T006 [Stage 2: Verify] AC-005/AC-006: `kubectl get svc -n ingress-nginx ingress-nginx-controller` shows EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com` (not `<pending>`) + `kubectl get ingress -n sdd-apps app-ingress` shows ADDRESS = ELB DNS name (not empty) — 004-4's previously-blocked ACs (Depends on T001)
