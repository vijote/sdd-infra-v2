# Technical Quality Checklist: IMDS Token Expiry — Bootstrap Instance-ID Publication

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-11
**Feature**: [IMDS Token Expiry Fix](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the root cause explicitly documented (300s IMDS token obtained at script start, expired by the end-of-script instance-id fetch; `curl -s` swallows the 401 → empty value → put-parameter ValidationException)?
- [x] CHK002 Is the fix mechanism explicit (fetch `INSTANCE_ID` at the top of the script alongside `PRIVATE_IP`, while the token is fresh)?
- [x] CHK003 Is the safety guard explicit (fail fast with a clear log line if `PRIVATE_IP` or `INSTANCE_ID` is empty)?
- [x] CHK004 Is the SSM parameter contract explicit (`/sdd-k8s-platform/kubeadm-bootstrap-instance-id` must equal the current control plane instance ID)?

## 2. Infrastructure & Security Hygiene
- [x] CHK005 Is the immutability assumption documented (EC2 instance ID never changes during the instance's lifetime, so early capture is safe)?
- [x] CHK006 Is the user-data constraint documented (fix takes effect only on the next control plane creation — user-data runs at first boot only)?
- [x] CHK007 Does CI verify via SSM only (no public API endpoint, no kubeconfig in CI)?
- [x] CHK008 Are the existing 003-11 gates unchanged (the fix unblocks them; it does not modify them)?

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK009 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK010 Is the AC ordering explicit (parameter equals instance ID → Flannel daemonset rolled out)?
- [x] CHK011 Does an AC verify the downstream effect (Flannel rollout) — proving the gate passed end-to-end?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- This is a 003-11 bug fix (instance-id publication step), discovered during the 003-12/004 rollout.
- Verification requires a fresh control plane (destroy + apply) — a persistent control plane keeps the old user-data.
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
