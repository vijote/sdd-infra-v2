# Technical Quality Checklist: Flannel Join-Param Delete Removal

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-06
**Feature**: [Flannel Join-Param Delete Removal](../spec.md)

## 1. Technical Contract Completeness
- [x] Terraform provisioner command is fully specified (delete step removed, waits retained)
- [x] SSM Parameter Store interaction is read-only (no delete)
- [x] No new AWS resources or resource changes
- [x] Collateral (003-7 workers) is documented as a one-time operational step

## 2. Infrastructure Contract Rigor
- [x] Target file and resource are explicit (`terraform/environments/dev/main.tf`, `null_resource "apply_flannel_cni"`)
- [x] The corrected command is byte-level specified (remove lines 87-91, keep the waits)
- [x] The persistent-control-plane assumption is stated and confirmed by the user

## 3. Machine-Verifiability
- [x] All acceptance criteria are executable in CI/CD (GitHub Actions)
- [x] AC-002/AC-003 use `grep -qF` (fixed strings) — no regex escaping
- [x] AC-004 uses `terraform plan -detailed-exitcode`
- [x] AC-005 uses `kubectl rollout status` via SSM Run Command

## 4. Security & Compliance
- [x] No secrets or credentials in the change
- [x] No IAM policy changes
- [x] No network exposure changes

## 5. Risk Assessment
- [x] Risk: removing the delete means a stale parameter from a *different* cluster could be read — mitigated by the parameter name being cluster-scoped (`/sdd-k8s-platform/`) and the control plane being the sole publisher
- [x] Risk: the 003-7 workers are already broken — mitigated by the one-time recreation step (AC-005)
