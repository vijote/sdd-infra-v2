# Technical Quality Checklist: Flannel Wait Bootstrap Complete

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-06
**Feature**: [Flannel Wait Bootstrap Complete](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the bootstrap-complete signal contract (exact parameter name, exact delete-at-start, exact poll loops) explicitly declared?
- [~] CHK002 Are Kubernetes API versions, CRDs, namespaces, and resource limits defined? — N/A (no K8s manifest change; Flannel manifest is fetched at runtime)
- [~] CHK003 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope)
- [x] CHK004 Is the root cause (Flannel command sent at SSM-agent registration ~20s, before `kubeadm init` completes → `kubectl` not installed / API server not up → 10-min poll timeout) documented and the fix mapped to it?
- [x] CHK005 Is the deployment method (existing terraform-apply workflow) explicitly stated?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Is the per-run signal justified (delete-at-start prevents stale parameter from a previous run)?
- [x] CHK007 Is the worker single-shot → poll change justified (worker may boot before control plane finishes; parameter is deleted at control-plane bootstrap start)?
- [x] CHK008 Is the instance re-launch impact (user_data hash change → control plane + workers re-launched) explicitly addressed?
- [~] CHK009 Are TLS termination and cert-manager specs defined? — N/A (no cluster scope)
- [~] CHK010 Are persistent storage retention/backup policies specified? — N/A (no storage scope)

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (exact parameter name, exact `delete-parameter` present, exact `seq 1 60` poll present)?
- [x] CHK013 Is the end-to-end proof (Flannel daemonset rollout via SSM) testable in CI?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
