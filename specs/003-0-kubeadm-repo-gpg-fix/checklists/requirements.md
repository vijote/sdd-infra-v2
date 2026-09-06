# Technical Quality Checklist: Kubeadm Repo GPG Fix

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-05
**Feature**: [Kubeadm Repo GPG Fix](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the corrected repo file (baseurl, gpgcheck, gpgkey) explicitly declared in the bootstrap contract?
- [~] CHK002 Are Kubernetes API versions, CRDs, namespaces, and resource limits defined? — N/A (no K8s scope change)
- [~] CHK003 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope)
- [x] CHK004 Is the root cause (`--add-repo` omits gpgkey → GPG check FAILED) documented and the fix mapped to it?
- [x] CHK005 Is the deployment method (existing terraform-apply workflow) explicitly stated?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Is GPG signature verification kept ON (`gpgcheck=1`, no `gpgcheck=0` bypass)?
- [x] CHK007 Are the existing containerd, AWS CLI, kubeadm config, and SSM publish steps left untouched?
- [x] CHK008 Is the instance-replacement impact (user_data hash change) explicitly addressed?
- [~] CHK009 Are TLS termination and cert-manager specs defined? — N/A (no cluster yet)
- [~] CHK010 Are persistent storage retention/backup policies specified? — N/A (no storage scope)

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (exact gpgkey URL, exact gpgcheck value, exact removed line)?
- [x] CHK013 Is the end-to-end proof (join command present in SSM) testable in CI?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
