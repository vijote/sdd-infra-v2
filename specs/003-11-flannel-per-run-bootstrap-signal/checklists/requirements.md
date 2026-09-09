# Technical Quality Checklist: Flannel Per-Run Bootstrap Signal

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-09
**Feature**: [Flannel Per-Run Bootstrap Signal](../spec.md)

## 1. Technical Contract Completeness
- [x] New SSM parameter is fully specified (name, type, publisher, value, ordering)
- [x] Control-plane bootstrap change is byte-level specified (IMDSv2 instance-ID read + `put-parameter`)
- [x] Flannel gate change is byte-level specified (poll instance-ID param until it equals `$INSTANCE_ID`)
- [x] Worker bootstrap change is byte-level specified (instance-ID gate before `eval`, `templatefile` injection)
- [x] Root cause is confirmed by a direct probe (param pointed to a different, later control plane)

## 2. Infrastructure Contract Rigor
- [x] Target files and resources are explicit (4 files: control-plane bootstrap, dev main.tf, worker main.tf, worker bootstrap)
- [x] The per-run signal semantics are stated for both apply types (fresh blocks, persistent returns immediately)
- [x] The `templatefile` placeholder syntax (`%{...}`) is specified
- [x] The existing contracts (003-4/003-6/003-9/003-10) are declared unchanged

## 3. Machine-Verifiability
- [x] All acceptance criteria are executable in CI/CD (GitHub Actions)
- [x] AC-002/AC-003/AC-004/AC-005 use `grep -qF` (fixed strings)
- [x] AC-006 uses `terraform plan -detailed-exitcode`
- [x] AC-007/AC-008 use `kubectl` via SSM Run Command

## 4. Security & Compliance
- [x] No secrets or credentials in the change (instance ID is not sensitive; param type is `String`, not `SecureString`)
- [x] No IAM policy changes (the node profile already has `ssm:PutParameter`/`ssm:GetParameter` on `/sdd-k8s-platform/*`)
- [x] No network exposure changes

## 5. Risk Assessment
- [x] Risk: the instance-ID param is stale from a previous run — mitigated by comparing to the current instance ID (a stale value never matches)
- [x] Risk: `templatefile` breaks if the placeholder is malformed — mitigated by `terraform validate` (AC-001) and the explicit `%{...}` syntax
- [x] Risk: worker boots before the control plane publishes the signal — mitigated by the 600s poll (same as the existing join-command poll)
- [x] Risk: the join command is fetched after the instance-ID gate, so it is guaranteed fresh (published immediately before the instance-ID param in the same bootstrap)
