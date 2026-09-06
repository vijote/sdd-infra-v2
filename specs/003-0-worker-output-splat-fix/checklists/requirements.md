# Technical Quality Checklist: Worker Output Splat Fix

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-06
**Feature**: [Worker Output Splat Fix](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the output contract (exact `for` expression, exact output name, exact description) explicitly declared?
- [~] CHK002 Are Kubernetes API versions, CRDs, namespaces, and resource limits defined? — N/A (no K8s scope change)
- [~] CHK003 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope)
- [x] CHK004 Is the root cause (`for_each` map + `[*]` list splat → "Unsupported attribute") documented and the fix mapped to it?
- [x] CHK005 Is the deployment method (existing terraform-apply workflow) explicitly stated?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Is the map-vs-list distinction justified (for_each=map, count=list) and the VPC `[*]` splat confirmed valid?
- [x] CHK007 Are the existing `main.tf`, `variables.tf`, `versions.tf`, and `bootstrap.sh` left untouched?
- [x] CHK008 Is the no-resource-replacement impact (output-only change) explicitly addressed?
- [~] CHK009 Are TLS termination and cert-manager specs defined? — N/A (no cluster scope)
- [~] CHK010 Are persistent storage retention/backup policies specified? — N/A (no storage scope)

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (exact removed splat, exact `for` expression, exact output count)?
- [x] CHK013 Is the end-to-end proof (clean `terraform plan` + 2-ID output) testable in CI?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
