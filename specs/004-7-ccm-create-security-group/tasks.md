# Execution Graph (DAG): CCM CreateSecurityGroup IAM Action

**Input**: Design documents from `/specs/004-7-ccm-create-security-group/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 1 implementation task + 5 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Terraform] In `terraform/modules/cluster-plumbing/main.tf`: in `aws_iam_role_policy.node_aws_ccm` `Action` list (EC2 section, line ~199–204), add `ec2:CreateSecurityGroup`, `ec2:AuthorizeSecurityGroupIngress`, `ec2:RevokeSecurityGroupIngress` alongside the existing `ec2:DeleteSecurityGroup` — the CCM's EnsureLoadBalancer flow (Create SG → Authorize 80/443 → Create LB) 403'd on CreateSecurityGroup (004-5 `--v=4` log: `SyncLoadBalancerFailed ... ec2:CreateSecurityGroup ... 403`); the full SG lifecycle is added in one change to avoid a second spec cycle for the next 403

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [x] T002 [Stage 2: Verify] AC-001: `terraform fmt -check -recursive && terraform validate` — exit 0, no diff (Depends on T001)
- [x] T003 [Stage 2: Verify] AC-002: `terraform plan -detailed-exitcode` — exit 2; plan shows exactly 1 `aws_iam_role_policy.node_aws_ccm` in-place update, zero other changes (Depends on T001)
- [x] T004 [Stage 2: Verify] AC-003: `terraform plan -no-color | grep -c 'ec2:CreateSecurityGroup'` returns `1` (and `ec2:AuthorizeSecurityGroupIngress` + `ec2:RevokeSecurityGroupIngress` present) (Depends on T001)
- [x] T005 [Stage 2: Verify] AC-004: after the next `terraform-apply` run — `kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 | grep -c 'SyncLoadBalancerFailed'` returns `0` (no new sync failures; force an immediate re-sync if needed: `kubectl delete pod -n kube-system -l app=aws-cloud-controller-manager`) (Depends on T001)
- [x] T006 [Stage 2: Verify] AC-005/AC-006: `kubectl get svc -n ingress-nginx ingress-nginx-controller` shows EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com` (not `<pending>`) + `kubectl get ingress -n sdd-apps app-ingress` shows ADDRESS = ELB DNS name (not empty) — 004-4's previously-blocked ACs (Depends on T001)
