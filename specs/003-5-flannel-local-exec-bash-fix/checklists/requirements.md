# Technical Quality Checklist: Flannel Local-Exec Bash Fix

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-06
**Feature**: [Flannel Local-Exec Bash Fix](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the provisioner contract (exact `interpreter` value, exact `command` preserved) explicitly declared?
- [~] CHK002 Are Kubernetes API versions, CRDs, namespaces, and resource limits defined? — N/A (no K8s manifest change; Flannel manifest is fetched at runtime)
- [~] CHK003 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope)
- [x] CHK004 Is the root cause (`local-exec` default `/bin/sh`=dash lacks `pipefail` → exit 2) documented and the fix mapped to it?
- [x] CHK005 Is the deployment method (existing terraform-apply workflow) explicitly stated?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Is the `interpreter` fix justified as the documented Terraform mechanism (vs. dropping `pipefail`)?
- [x] CHK007 Are the existing SSM send-command, poll loop, and status checks left byte-for-byte unchanged?
- [x] CHK008 Is the null-resource re-run impact (provisioner config change → re-issue SSM command) explicitly addressed?
- [~] CHK009 Are TLS termination and cert-manager specs defined? — N/A (no cluster scope)
- [~] CHK010 Are persistent storage retention/backup policies specified? — N/A (no storage scope)

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (exact `interpreter` value, exact preserved `set -euo pipefail` line)?
- [x] CHK013 Is the end-to-end proof (Flannel daemonset rollout via SSM) testable in CI?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
