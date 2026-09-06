# Technical Quality Checklist: IMDSv2 Private IP Fix

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-05
**Feature**: [IMDSv2 Private IP Fix](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the IMDSv2 token flow (PUT token + token header on metadata call) explicitly declared in the bootstrap contract?
- [~] CHK002 Are Kubernetes API versions, CRDs, namespaces, and resource limits defined? — N/A (no K8s scope change)
- [~] CHK003 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope)
- [x] CHK004 Is the root cause (IMDSv2 401 → empty PRIVATE_IP → `hostport :6443` failure) documented and the fix mapped to it?
- [x] CHK005 Is the deployment method (existing terraform-apply workflow) explicitly stated?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Is the KubeletConfiguration GVK correction (`kubelet.k8s.io/v1beta1`) explicitly declared?
- [x] CHK007 Are the existing containerd, kubernetes repo, AWS CLI, and SSM publish steps left untouched?
- [x] CHK008 Is the instance-replacement impact (user_data hash change) explicitly addressed?
- [~] CHK009 Are TLS termination and cert-manager specs defined? — N/A (no cluster yet)
- [~] CHK010 Are persistent storage retention/backup policies specified? — N/A (no storage scope)

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (exact token header, exact GVK, exact SSM parameter path)?
- [x] CHK013 Is the end-to-end proof (join command present in SSM) testable in CI?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
