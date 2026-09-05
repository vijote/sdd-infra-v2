# Technical Quality Checklist: Control Plane (kubeadm init)

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-05
**Feature**: [Control Plane](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Are all Terraform variable types, defaults, and module input/output interfaces explicitly declared?
- [x] CHK002 Is the kubeadm config (cert SANs, pod CIDR, control plane endpoints) explicitly specified?
- [~] CHK003 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope)
- [x] CHK004 Are the upstream inputs (vpc_id, private_subnet_ids, control plane SG, instance profile) explicitly typed and sourced?
- [x] CHK005 Are the downstream outputs (instance ID, private IP, SSM join command) explicitly declared for 003-3?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Is the control plane in a private subnet with no public IP?
- [x] CHK007 Is the join command stored as an SSM SecureString (not in user-data plaintext or repo)?
- [x] CHK008 Does CI verify via SSM only (no public API endpoint, no kubeconfig in CI)?
- [~] CHK009 Are TLS termination and cert-manager specs defined? — N/A (kubeadm self-signed certs only)
- [~] CHK010 Are persistent storage retention/backup policies specified? — N/A (no data layer)

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (instance type, pod CIDR, SSM parameter path, timeouts)?
- [x] CHK013 Is the bootstrap model unambiguous (user-data runs init once; CI polls, never re-runs)?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
