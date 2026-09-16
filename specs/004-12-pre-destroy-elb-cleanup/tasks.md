# Execution Graph (DAG): Pre-Destroy CCM ELB Cleanup

**Input**: Design documents from `/specs/004-12-pre-destroy-elb-cleanup/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 1 implementation task + 8 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Workflow] In `.github/workflows/terraform-destroy.yml`: add a `Pre-Destroy ELB Cleanup` step positioned AFTER the `Terraform Init` step and BEFORE the `Terraform Destroy` step. The step's `run` block (bash, no `echo`/`set -x` per constitution P6): (1) resolve the VPC by cluster tag — `VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag-key,Values=kubernetes.io/cluster/sdd-k8s-platform" --query 'Vpcs[0].VpcId' --output text)`; (2) list Classic ELBs in that VPC — `LB_NAMES=$(aws elb describe-load-balancers --query "LoadBalancerDescriptions[?VpcId=='${VPC_ID}'].LoadBalancerName" --output text)`; (3) for each name, `aws elb delete-load-balancer --load-balancer-name "$LB"` then poll `aws elb describe-load-balancers --load-balancer-names "$LB"` (up to 30 × 10s) until the name is gone (ENI released). Guard: if `VPC_ID` is empty or `None` (VPC already destroyed) or `LB_NAMES` is empty/`None`, the step is a no-op and exits 0. No Terraform, module, manifest, or IAM changes — this is the ONLY file touched (AC-008)

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T002 [Stage 2: Verify] AC-001: `actionlint .github/workflows/terraform-destroy.yml` — exit 0 (Depends on T001)
- [ ] T003 [Stage 2: Verify] AC-002: `grep -c 'Pre-Destroy ELB Cleanup' .github/workflows/terraform-destroy.yml` — returns `1` (step present) (Depends on T001)
- [ ] T004 [Stage 2: Verify] AC-003: step ordering — `grep -n 'Pre-Destroy ELB Cleanup\|Terraform Destroy' .github/workflows/terraform-destroy.yml` shows the cleanup step's line number < the `Terraform Destroy` step's line number (Depends on T001)
- [ ] T005 [Stage 2: Verify] AC-004: `grep -c 'kubernetes.io/cluster/sdd-k8s-platform' .github/workflows/terraform-destroy.yml` — returns `1` (VPC resolved by cluster tag) (Depends on T001)
- [ ] T006 [Stage 2: Verify] AC-005: `grep -c 'aws elb delete-load-balancer' .github/workflows/terraform-destroy.yml` — returns `1` (Classic ELB delete present) (Depends on T001)
- [ ] T007 [Stage 2: Verify] AC-006: `grep -c 'aws elb describe-load-balancers' .github/workflows/terraform-destroy.yml` — returns `2` (one for the list, one for the deletion wait loop) (Depends on T001)
- [ ] T008 [Stage 2: Verify] AC-007: `grep -c 'github.event.inputs.confirm' .github/workflows/terraform-destroy.yml` — returns `2` (type-"destroy" confirmation gate retained) (Depends on T001)
- [ ] T009 [Stage 2: Verify] AC-008: `git diff --name-only` — shows ONLY `.github/workflows/terraform-destroy.yml` modified (no Terraform drift) (Depends on T001)
