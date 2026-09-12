# Execution Graph (DAG): Flannel VXLAN Security Group Rules

**Input**: Design documents from `/specs/003-14-flannel-vxlan-sg/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 1 implementation task + 4 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Bootstrap] Add 2 ingress blocks (UDP 8472 VXLAN, TCP 4240 Flannel API, `cidr_blocks = [var.vpc_cidr]`) to BOTH `aws_security_group.control_plane` and `aws_security_group.worker` in `terraform/modules/cluster-plumbing/main.tf` (Depends on: none)

## Stage 2: Verification (CI / user-managed, per P5/P6)

- [ ] T002 [Stage 2: Verify] Static: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` — plan must show in-place update of the two SGs only, zero replacements (AC-001, AC-002) (Depends on: T001)
- [ ] T003 [Stage 2: Verify] SSM: both SGs expose 8472/udp + 4240/tcp from vpc_cidr (AC-003) (Depends on: T002)
- [ ] T004 [Stage 2: Verify] SSM: cross-node pod→pod DNS — worker pod `nslookup kubernetes.default` succeeds (AC-004) (Depends on: T003)
- [ ] T005 [Stage 2: Verify] SSM: 005 PVC `mysql-data-mysql-0` phase `Bound` (AC-005) (Depends on: T004)

## Dependencies

```
T001 → T002 → T003 → T004 → T005
```

## Notes
- T001 is the only agent-executed task; T002–T005 run in CI / by the user (constitution P5/P6).
- T004 is the direct proof of the fix; T005 is the downstream proof (original symptom resolved).
