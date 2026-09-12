# Technical Quality Checklist: EBS CSI Driver K8s Version Skew Fix

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-12
**Feature**: 004-3-ebs-csi-k8s-version-skew

## Infrastructure Contracts
- [x] EBS CSI ref pinned to a K8s 1.28-compatible release (`v1.28.0`) — matches cluster `K8S_VERSION="1.28.0"`
- [x] Exact `apply -k` URL pinned verbatim (user-provided): `github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=v1.28.0`
- [x] No new AWS resources / IAM / security groups (reuses control-plane SSM channel)
- [x] No manifest changes — only the driver ref + trigger change in `dev/main.tf`

## Failure Mode & Recovery
- [x] Root cause documented: `spec.nodeAllocatableUpdatePeriodSeconds` is a K8s 1.33+ CSIDriver field; 1.28 API server strict-decode rejects it
- [x] Partial state from the failed `release-1.65` run handled by idempotent re-apply (same-named resources updated in place; missing CSIDriver created)
- [x] `set -e` fail-fast retained (004-2) — a future skew failure aborts the SSM command and fails the apply
- [x] Re-trigger via changed `ebs_csi_ref` value (no manual `terraform taint` needed)

## Verification (CI / user-managed, per P5/P6)
- [x] AC-001/AC-002 static: `terraform fmt -check -recursive && terraform validate`; `terraform plan -detailed-exitcode`
- [x] AC-003: `apply -k ...?ref=v1.28.0` exits `Success` (no CSIDriver decode error)
- [x] AC-004: `kubectl get csidriver ebs.csi.aws.com` succeeds
- [x] AC-005: `kubectl rollout status` for `deployment/ebs-csi-controller` + `daemonset/ebs-csi-node` (label-agnostic)

## Constraints
- [x] Spec < 200 lines
- [x] No unit/E2E tests — direct AWS CLI + SSM verification only
- [x] Version pairing rule documented (driver minor ↔ cluster minor) for future upgrades
