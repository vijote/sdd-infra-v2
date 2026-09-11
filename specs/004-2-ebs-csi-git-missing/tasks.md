# Execution Graph (DAG): EBS CSI Install — git Missing on Control Plane

**Input**: Design documents from `/specs/004-2-ebs-csi-git-missing/`
**Prerequisites**: `plan.md` (File Impact Matrix & Rollout Stages), `spec.md` (Contracts & ACs)
**Estimated Tasks**: 5 (2 implementation, 3 verification)
**Estimated Duration**: Short (single-purpose fix, 2 files)
**Dependency Chain**: T001 → T002 → T003/T004/T005

## Stage 1: Implementation

- [x] T001 [Stage 1: Bootstrap] Add `dnf install -y git` to `terraform/modules/control-plane/bootstrap.sh` (dedicated line after the k8s install block, before the AWS CLI install) so fresh control planes have `git` at first boot
- [x] T002 [Stage 1: App Infra] Modify `null_resource.apply_app_infrastructure` in `terraform/environments/dev/main.tf`: prepend `set -e` as the first SSM command entry, add `dnf install -y git` as the next entry (before the namespace create), and add `git_bootstrap = "1"` to `triggers` (Depends on T001)

## Stage 2: Verification (CI / user-managed, per P5/P6)

- [ ] T003 [Stage 2: Static] Terraform syntax/format/plan valid — `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (AC-001, AC-002) (Depends on T002)
- [ ] T004 [Stage 2: SSM] `git` installed on the control plane — SSM `git --version` → `^git version` (AC-003) (Depends on T002)
- [ ] T005 [Stage 2: SSM] EBS CSI ready — SSM `kubectl rollout status deployment/ebs-csi-controller -n kube-system --timeout=300s && kubectl rollout status daemonset/ebs-csi-node -n kube-system --timeout=300s` (AC-004, AC-005) (Depends on T002)

## Dependencies

```
T001 (bootstrap.sh: git)
 └── T002 (main.tf: set -e + dnf install git + trigger)
      ├── T003 (static: fmt/validate/plan)
      ├── T004 (SSM: git --version)
      └── T005 (SSM: EBS CSI rollout status)
```

## Parallelization

- T001 and T002 are sequential (T002's SSM command mirrors T001's bootstrap change; keep them consistent).
- T003, T004, T005 are independent verification gates — can run in parallel in CI once T002 lands.

## Verification Task Mappings

| Task | AC | Channel |
|------|----|---------|
| T003 | AC-001, AC-002 | Static (existing `terraform-apply.yml`) |
| T004 | AC-003 | SSM Run Command on control plane |
| T005 | AC-004, AC-005 | SSM Run Command on control plane |
