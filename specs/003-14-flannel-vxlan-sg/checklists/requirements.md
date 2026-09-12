# Technical Quality Checklist: Flannel VXLAN Security Group Rules

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-12
**Feature**: 003-14-flannel-vxlan-sg

## Root Cause & Diagnosis
- [x] Root cause documented: Flannel VXLAN (UDP 8472) + Flannel API (TCP 4240) missing from both node SGs → cross-node pod→pod dropped
- [x] Diagnosis evidence recorded: worker-pod `nslookup` to CoreDNS pod IP times out; node-level `curl`/`getent` to EC2 API succeed (isolates pod-network from node-network)
- [x] Explains downstream symptom: EBS CSI controller pod can't resolve EC2 endpoint → `CreateVolume` `context deadline exceeded` → 005 PVC `Pending`
- [x] Explains why Flannel showed 3/3 Ready (readiness = subnet acquisition via API 6443, not tunnel health)

## Infrastructure Contracts
- [x] Exact ports/protocols pinned: UDP 8472 (VXLAN), TCP 4240 (Flannel API)
- [x] Rules scoped to `var.vpc_cidr` (10.0.0.0/16) — no internet exposure
- [x] Symmetric: added to BOTH `control_plane` and `worker` SGs (bidirectional traffic)
- [x] In-place SG update — no instance replacement, no cluster rebuild, no Flannel restart
- [x] No new AWS resources; no manifest changes

## Verification (CI / user-managed, per P5/P6)
- [x] AC-001/AC-002 static: `terraform fmt -check -recursive && terraform validate`; `terraform plan -detailed-exitcode`
- [x] AC-003: both SGs show 8472/udp + 4240/tcp ingress (AWS CLI)
- [x] AC-004: cross-node pod→pod DNS — worker pod `nslookup kubernetes.default` succeeds (SSM)
- [x] AC-005: 005 PVC `mysql-data-mysql-0` phase `Bound` (SSM)

## Constraints
- [x] Spec < 200 lines
- [x] No unit/E2E tests — direct AWS CLI + SSM verification only
- [x] Downstream (005 PVC binding) noted as the real-world proof of the fix
