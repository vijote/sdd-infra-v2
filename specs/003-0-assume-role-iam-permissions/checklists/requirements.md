# Technical Quality Checklist: Assume Role IAM Permissions

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-05
**Feature**: [Assume Role IAM Permissions](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the CloudFormation policy block (name, action, resource) explicitly declared?
- [~] CHK002 Are Kubernetes API versions, CRDs, namespaces, and resource limits defined? — N/A (no K8s scope)
- [~] CHK003 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope)
- [x] CHK004 Is the root cause (PowerUserAccess excludes `iam:*`) documented and the fix mapped to it?
- [x] CHK005 Is the deployment method (user-managed CloudFormation update) explicitly stated?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Is the wildcard `iam:*` scope an explicit, documented user decision (not an accident)?
- [x] CHK007 Is the role's reachability boundary (OIDC → bootstrap → role chaining) preserved unchanged?
- [x] CHK008 Are the trust policy and existing `TerraformStateAccess` policy left untouched?
- [~] CHK009 Are TLS termination and cert-manager specs defined? — N/A (no cluster yet)
- [~] CHK010 Are persistent storage retention/backup policies specified? — N/A (no storage scope)

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (exact policy name, exact action, exact role names)?
- [~] CHK013 Are failure recovery paths (node/pod recreation) testable? — N/A (no nodes yet)

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
