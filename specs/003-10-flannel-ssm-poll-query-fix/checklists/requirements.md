# Technical Quality Checklist: Flannel SSM Poll Query Fix

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-09
**Feature**: [Flannel SSM Poll Query Fix](../spec.md)

## 1. Technical Contract Completeness
- [x] Terraform provisioner command is fully specified (correct the `--query` JMESPath expression)
- [x] SSM Run Command interaction is unchanged (same document, same instance, same send-command)
- [x] No new AWS resources or resource changes
- [x] Root cause is confirmed by a direct SSM probe (command `Success` in 0.913s, but poll query returns `null`)

## 2. Infrastructure Contract Rigor
- [x] Target file and resource are explicit (`terraform/environments/dev/main.tf`, `null_resource "apply_flannel_cni"`, line 138)
- [x] The corrected query is byte-level specified (`CommandInvocation.Status || Status`)
- [x] The flat-vs-wrapped response shape is documented and the `||` fallback is justified
- [x] The relationship to 003-9 (KUBECONFIG made the command succeed) is stated

## 3. Machine-Verifiability
- [x] All acceptance criteria are executable in CI/CD (GitHub Actions)
- [x] AC-002/AC-003 use `grep -qF` (fixed strings) — no regex escaping, no `--` flag-parsing issue
- [x] AC-003 pattern (`'CommandInvocation.Status'` with closing quote) verified: matches pre-fix, no false-positive post-fix
- [x] AC-004 uses `terraform plan -detailed-exitcode`
- [x] AC-005 uses `kubectl rollout status` via SSM Run Command

## 4. Security & Compliance
- [x] No secrets or credentials in the change
- [x] No IAM policy changes
- [x] No network exposure changes

## 5. Risk Assessment
- [x] Risk: a different AWS CLI version returns the wrapped shape — mitigated by the `||` fallback (`CommandInvocation.Status || Status` handles both)
- [x] Risk: the query still returns empty for a genuinely pending command — mitigated by the existing `|| STATUS="Pending"` fallback and the 600s timeout
