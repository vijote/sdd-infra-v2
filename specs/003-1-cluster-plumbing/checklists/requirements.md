# Technical Quality Checklist: Cluster Plumbing (Security Groups + IAM)

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-05
**Feature**: [Cluster Plumbing](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Are all Terraform variable types, defaults, and module input/output interfaces explicitly declared?
- [~] CHK002 Are Kubernetes API versions, CRDs, namespaces, and resource limits defined? — N/A (no workloads)
- [~] CHK003 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope)
- [x] CHK004 Are the upstream inputs (vpc_id, vpc_cidr) explicitly typed and sourced from `002-vpc-foundation`?
- [x] CHK005 Are the downstream outputs (SG IDs, instance profile name) explicitly declared for 003-2/003-3?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Are Security Group ingress rules constrained to VPC CIDR only (no 0.0.0.0/0)?
- [x] CHK007 Is the IAM role bounded to managed policies (SSM + ECR read-only) — no inline wildcard policies?
- [x] CHK008 Is the instance profile the only IAM surface (no user credentials, no static keys)?
- [~] CHK009 Are TLS termination and cert-manager specs defined? — N/A (no cluster yet)
- [~] CHK010 Are persistent storage retention/backup policies specified? — N/A (no storage scope)

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (exact ports, exact CIDRs, exact policy names)?
- [~] CHK013 Are failure recovery paths (node/pod recreation) testable? — N/A (no nodes yet)

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
