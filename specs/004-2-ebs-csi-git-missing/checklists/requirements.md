# Technical Quality Checklist: EBS CSI Install — git Missing on Control Plane

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-10
**Feature**: [EBS CSI Install — git Missing](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the root cause explicitly documented (`kubectl apply -k github.com/...` needs `git` on the control plane; AL2023 has none → exit 1, swallowed by the no-`set -e` SSM command)?
- [x] CHK002 Is the fix mechanism explicit (install `git` via `dnf` — bootstrap.sh for fresh clusters + SSM `dnf install -y git` for the running one)?
- [x] CHK003 Is the `null_resource.apply_app_infrastructure` modification explicit (git-install command, `set -e` first entry, `git_bootstrap` trigger)?
- [x] CHK004 Is the EBS CSI install command unchanged (only the control plane gains `git`)?

## 2. Infrastructure & Security Hygiene
- [x] CHK005 Does CI verify via SSM only (no public API endpoint, no kubeconfig in CI)?
- [x] CHK006 Is the fix idempotent and re-runnable (`dnf install -y git`, `kubectl apply -k`)?
- [x] CHK007 Is failure visibility added (`set -e` as the first SSM command so a failed step aborts the rest)?
- [x] CHK008 Is the bootstrap-instance-id gate (003-11) preserved?

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK009 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK010 Is the AC ordering explicit (git installed → EBS CSI rollout → apply -k exit 0)?
- [x] CHK011 Is the EBS CSI readiness AC label-agnostic (`rollout status` by name, not a pod label selector)?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- AC-004 (EBS CSI pods Ready) depends on `003-12-flannel-cidr-mismatch` (working pod networking).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
