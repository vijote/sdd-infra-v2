# Architecture Delta: Flannel VXLAN Security Group Rules

**Branch**: `003-14-flannel-vxlan-sg` | **Date**: 2026-09-12 | **Status**: Draft

## 1. File Impact Matrix

| File | Operation | Description |
|------|-----------|-------------|
| `terraform/modules/cluster-plumbing/main.tf` | Modify | Add 2 ingress blocks (UDP 8472 VXLAN, TCP 4240 Flannel API, `var.vpc_cidr`) to BOTH `aws_security_group.control_plane` and `aws_security_group.worker` |

No new AWS resources, no new module, no manifest changes, no `bootstrap.sh` change.

## 2. Rollout Stages

### Stage 1: Implementation
- **T001** — Add the 4 ingress blocks (2 per SG) to `cluster-plumbing/main.tf`. Pure HCL; `terraform fmt` + `validate` must pass.

### Stage 2: Verification (CI / user-managed, per P5/P6)
- **T002** — Static: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (AC-001, AC-002). Plan must show **in-place update** of the two SGs only (`~` on `ingress`), zero replacements.
- **T003** — SSM: both SGs expose 8472/udp + 4240/tcp (AC-003).
- **T004** — SSM: cross-node pod→pod DNS — worker pod `nslookup kubernetes.default` succeeds (AC-004).
- **T005** — SSM: 005 PVC `mysql-data-mysql-0` phase `Bound` (AC-005).

## 3. Key Design Decisions

- **Why both ports**: 8472/UDP is the VXLAN data plane (the actual pod traffic); 4240/TCP is the Flannel API (subnet lease coordination). Both are node-to-node; both scoped to `var.vpc_cidr` (10.0.0.0/16) — no internet exposure.
- **Why both SGs**: traffic is bidirectional (worker↔control-plane); each node's SG must accept inbound VXLAN from the other.
- **In-place, no restart**: SG ingress rules are mutable in place. VXLAN packets flow the moment the rules exist — no flanneld restart, no pod restart. The EBS CSI external-provisioner retries `CreateVolume` automatically (~45s observed), so the 005 PVC binds without re-applying 005.
- **No `lifecycle`/`ignore_changes`**: the rules are declarative and stable; no drift suppression needed.
- **Verification order matters**: T004 (DNS) is the direct proof of the fix; T005 (PVC Bound) is the downstream proof that the original symptom (EBS CSI timeout) is resolved.

## 4. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Plan shows SG replacement instead of in-place update | SG ingress changes are never ForceNew; if plan shows replacement, stop and inspect (would indicate an unintended attribute change) |
| PVC still Pending after SG fix | Re-check EBS CSI controller logs for a *different* error (e.g. IAM); the DNS path is proven by T004 first, so a T005-only failure is isolated to the EC2 call |
| 4240 conflicts with an existing rule | No existing 4240 rule in either SG (verified in 003-1); duplicate-port rules with different protocols are legal in AWS |

## 5. Out of Scope
- No Flannel re-apply, no CoreDNS changes, no 005 manifest changes.
- No NAT/endpoint changes (node-level egress already proven working).
- No other SG ports (kubelet 10250, API 6443, etcd 2379-2380 already present).
