# Execution Graph (DAG): EBS CSI Driver K8s Version Skew Fix

**Input**: Design documents from `/specs/004-3-ebs-csi-k8s-version-skew/`
**Prerequisites**: `plan.md` (File Impact Matrix & Rollout Stages), `spec.md` (Contracts & ACs)
**Estimated Tasks**: 4 (1 implementation, 3 verification)
**Estimated Duration**: Short (single-file ref re-pin)
**Dependency Chain**: T001 → T002/T003/T004

## Stage 1: Implementation

- [x] T001 [Stage 1: App Infra] In `terraform/environments/dev/main.tf` `null_resource.apply_app_infrastructure`: change the EBS CSI `apply -k` ref from `release-1.65` to `v1.28.0` (K8s 1.28-compatible driver), change trigger `ebs_csi_ref` from `"release-1.65"` to `"v1.28.0"`, and update the resource comment to reflect the new ref

## Stage 2: Verification (CI / user-managed, per P5/P6)

- [ ] T002 [Stage 2: Static] Terraform syntax/format/plan valid — `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (AC-001, AC-002) (Depends on T001)
- [ ] T003 [Stage 2: SSM] EBS CSI `apply -k ...?ref=v1.28.0` exits `Success` (no CSIDriver decode error) (AC-003) (Depends on T001)
- [ ] T004 [Stage 2: SSM] CSIDriver registered + EBS CSI ready — SSM `kubectl get csidriver ebs.csi.aws.com && kubectl rollout status deployment/ebs-csi-controller -n kube-system --timeout=300s && kubectl rollout status daemonset/ebs-csi-node -n kube-system --timeout=300s` (AC-004, AC-005) (Depends on T001)

## Dependencies

```
T001 (main.tf: re-pin EBS CSI ref to v1.28.0 + trigger)
 ├── T002 (static: fmt/validate/plan)
 ├── T003 (SSM: apply -k v1.28.0 succeeds)
 └── T004 (SSM: CSIDriver + rollout status)
```

## Parallelization

- T002, T003, T004 are independent verification gates — can run in parallel in CI once T001 lands.

## Verification Task Mappings

| Task | AC | Channel |
|------|----|---------|
| T002 | AC-001, AC-002 | Static (existing `terraform-apply.yml`) |
| T003 | AC-003 | SSM Run Command on control plane |
| T004 | AC-004, AC-005 | SSM Run Command on control plane |
