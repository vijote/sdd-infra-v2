# Architecture Delta: EBS CSI Driver K8s Version Skew Fix

**Branch**: `004-3-ebs-csi-k8s-version-skew` | **Date**: 2026-09-12 | **Status**: Draft

## 1. File Impact Matrix

| File | Op | Purpose / Exports |
|------|----|-------------------|
| `terraform/environments/dev/main.tf` | Modify | `null_resource.apply_app_infrastructure`: (a) change the EBS CSI `apply -k` ref from `release-1.65` to `v1.28.0` (K8s 1.28-compatible driver), (b) change trigger `ebs_csi_ref` from `"release-1.65"` to `"v1.28.0"` so the provisioner re-runs, (c) update the resource comment to reflect the new ref. |

No new AWS resources. No new module. No manifest changes. No `bootstrap.sh` change — this rolls out **in-place** (no control-plane replacement; workers stay joined).

## 2. Architecture Delta

### 2.1 Root cause
EBS CSI `release-1.65` targets K8s 1.33+ — its `CSIDriver` manifest sets `spec.nodeAllocatableUpdatePeriodSeconds`, a field absent from the K8s 1.28 API. The 1.28 API server rejects it (`strict decoding error: unknown field "spec.nodeAllocatableUpdatePeriodSeconds"`, exit 1). The `apply -k` created all other resources (SAs, RBAC, `ebs-csi-controller` Deployment, PDB, `ebs-csi-node` DaemonSet) then aborted on the CSIDriver; `set -e` (004-2) surfaced the failure.

### 2.2 Fix mechanism
Re-pin the driver to **`v1.28.0`** — the release matching the cluster's K8s minor version (`K8S_VERSION="1.28.0"` in `bootstrap.sh`). The v1.28.0 manifest's CSIDriver is compatible with the 1.28 API server.

**Version pairing rule**: EBS CSI driver minor ↔ cluster K8s minor. If the cluster is ever upgraded (e.g. K8s 1.33+), the driver ref must be re-pinned in the same change.

### 2.3 Partial-state handling
The failed `release-1.65` run left same-named resources (SAs, RBAC, Deployment, PDB, DaemonSet) without the CSIDriver. Re-applying `v1.28.0` updates them in place (idempotent `kubectl apply`) and creates the missing `CSIDriver ebs.csi.aws.com`. No manual cleanup required.

### 2.4 Re-trigger
Changing `ebs_csi_ref` to `"v1.28.0"` changes the trigger hash, so the next `terraform apply` re-runs the provisioner → re-applies the full app-infra command list (namespace → EBS CSI v1.28.0 → StorageClass → ingress), fail-fast under `set -e`.

## 3. Provisioning & Rollout Stages

1. **Terraform apply** — trigger change re-runs `apply_app_infrastructure` (in-place; no instance replacement).
2. **SSM: re-apply app infra** — `set -e` → `dnf install -y git` (no-op) → namespace → **EBS CSI `apply -k ...?ref=v1.28.0` (now succeeds)** → StorageClass → ingress.
3. **Pod readiness** — EBS CSI controller Deployment + node DaemonSet become Ready (requires working Flannel pod networking from 003-12).

## 4. Verification Gates (CI / user-managed, per P5/P6)

- **AC-001/AC-002** (static, existing `terraform-apply.yml`): `terraform fmt -check -recursive && terraform validate`; `terraform plan -detailed-exitcode`.
- **AC-003** (SSM): `kubectl apply -k ...?ref=v1.28.0` exits `Success` (no CSIDriver decode error).
- **AC-004** (SSM): `kubectl get csidriver ebs.csi.aws.com` succeeds.
- **AC-005** (SSM): `kubectl rollout status deployment/ebs-csi-controller` + `daemonset/ebs-csi-node` (label-agnostic, `-n kube-system`, `--timeout=300s`).

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `v1.28.0` ref does not exist in the repo | User-provided, verbatim-pinned URL; AC-003 fails fast under `set -e` if the ref is bad. |
| EBS CSI pods stay `ContainerCreating` if Flannel is broken | 003-12 (CIDR fix) is a prerequisite — AC-005 depends on working pod networking. |
| Stale `release-1.65` resources conflict with v1.28.0 | Same resource names; `kubectl apply` updates in place (idempotent). CSIDriver is created fresh. |
| Provisioner re-runs the whole command list | Intended — all steps are idempotent (`kubectl apply`); re-run is safe. |
