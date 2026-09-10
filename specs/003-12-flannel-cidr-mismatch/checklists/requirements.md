# Technical Quality Checklist: Flannel CNI CIDR Mismatch Fix

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-10
**Feature**: [Flannel CNI CIDR Mismatch Fix](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the root cause explicitly documented (kubeadm podSubnet `192.168.0.0/16` vs Flannel `net-conf.json` `Network: 10.244.0.0/16`)?
- [x] CHK002 Is the fix mechanism explicit (sed the Network CIDR in the pinned v0.24.0 stock manifest before apply + daemonset restart)?
- [x] CHK003 Is the target ConfigMap contract explicit (`kube-flannel-cfg` `net-conf.json` `Network: 192.168.0.0/16`, `Backend.Type: vxlan`)?
- [x] CHK004 Is the `null_resource.apply_flannel_cni` modification explicit (sed step, rollout restart, `pod_cidr` trigger)?

## 2. Infrastructure & Security Hygiene
- [x] CHK005 Does CI verify via SSM only (no public API endpoint, no kubeconfig in CI)?
- [x] CHK006 Is the fix idempotent and re-runnable (sed + apply + restart)?
- [x] CHK007 Does the fix avoid the 003-6 JSON-escaping gotcha (sed on the file, not an inline ConfigMap patch)?
- [x] CHK008 Is the bootstrap-instance-id gate (003-11) preserved so the apply blocks until the control plane is ready?

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK009 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK010 Is the AC ordering explicit (ConfigMap CIDR → daemonset rollout → CoreDNS Ready)?
- [x] CHK011 Does an AC verify pods actually get pod IPs (CoreDNS Ready) — closing the gap 003-11 missed?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- This is a 003 bug fix (Flannel CNI), not a 004 change.
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
