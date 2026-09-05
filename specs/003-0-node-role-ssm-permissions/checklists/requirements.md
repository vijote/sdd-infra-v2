# Technical Quality Checklist: Node Role SSM Permissions

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-05
**Feature**: [Node Role SSM Permissions](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the inline policy (name, actions, resource ARN) explicitly declared in HCL?
- [~] CHK002 Are Kubernetes API versions, CRDs, namespaces, and resource limits defined? — N/A (no K8s scope)
- [~] CHK003 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope)
- [x] CHK004 Is the root cause (managed policy lacks Put/Get Parameter) documented and the fix mapped to it?
- [x] CHK005 Is the deployment method (existing terraform-apply workflow) explicitly stated?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Is the SSM scope least-privilege (specific actions + `parameter/sdd-k8s-platform/*` only)?
- [x] CHK007 Are the existing role trust policy and managed attachments left untouched?
- [x] CHK008 Is the shared-profile impact (003-2 publish + 003-3 read) explicitly addressed?
- [~] CHK009 Are TLS termination and cert-manager specs defined? — N/A (no cluster yet)
- [~] CHK010 Are persistent storage retention/backup policies specified? — N/A (no storage scope)

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (exact policy name, exact actions, exact resource ARN)?
- [~] CHK013 Are failure recovery paths (node/pod recreation) testable? — N/A (no nodes yet)

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
