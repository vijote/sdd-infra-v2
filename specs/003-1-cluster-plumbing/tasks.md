# Execution Graph (DAG): Cluster Plumbing (Security Groups + IAM)

**Input**: Design documents from `/specs/003-1-cluster-plumbing/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~30 min (agent file edits) + CI verification

---

## Stage 1: Cluster Plumbing Module

- [x] T001 [Stage 1: Module] Declare Terraform >= 1.5.0, AWS provider >= 5.0.0, and provider config in `terraform/modules/cluster-plumbing/versions.tf`
- [x] T002 [Stage 1: Module] Define input variables (vpc_id, vpc_cidr, tags) in `terraform/modules/cluster-plumbing/variables.tf`
- [x] T003 [Stage 1: Module] Implement control plane SG (ingress 6443, 2379-2380, 22 from VPC CIDR), worker SG (ingress 10250, 30000-32767, 22 from VPC CIDR), IAM role (AmazonSSMManagedInstanceCore + AmazonEC2ContainerRegistryReadOnly), and IAM instance profile in `terraform/modules/cluster-plumbing/main.tf` (Depends on T001, T002)
- [x] T004 [Stage 1: Module] Export outputs (control_plane_security_group_id, worker_security_group_id, node_iam_instance_profile_name) in `terraform/modules/cluster-plumbing/outputs.tf` (Depends on T003)

---

## Stage 2: Dev Environment Wiring

- [x] T005 [Stage 2: Dev Env] Add `module "cluster_plumbing"` instantiation (source `../../modules/cluster-plumbing`, vpc_id = `module.vpc.vpc_id`, vpc_cidr = `var.vpc_cidr`) in `terraform/environments/dev/main.tf` (Depends on T004)
- [x] T006 [Stage 2: Dev Env] Add root outputs (control_plane_security_group_id, worker_security_group_id, node_iam_instance_profile_name) for 003-2/003-3 in `terraform/environments/dev/outputs.tf` (Depends on T005)

---

## Stage 3: Verification (CI-only — executed in GitHub Actions, never locally)

- [ ] T007 [Stage 3: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T006)
- [ ] T008 [Stage 3: Verify] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`) (Depends on T007)
- [ ] T009 [Stage 3: Verify] AC-003: Control plane SG exists with 6443 ingress from VPC CIDR (Depends on T008)
- [ ] T010 [Stage 3: Verify] AC-004: Worker SG exists with 30000-32767 ingress from VPC CIDR (Depends on T008)
- [ ] T011 [Stage 3: Verify] AC-005: IAM instance profile exists and attaches a role (Depends on T008)
- [ ] T012 [Stage 3: Verify] AC-006: IAM role has SSM managed policy attached (Depends on T011)

---

## Dependencies / Execution Order

```
T001 ─┐
      ├─ T003 ─ T004 ─ T005 ─ T006 ─ T007 ─ T008 ─┬─ T009
T002 ─┘                                            ├─ T010
                                                   ├─ T011 ─ T012
```

- **Parallelizable**: T001 + T002 (independent module scaffolding)
- **Sequential**: T003 → T004 → T005 → T006 (module → wiring chain)
- **CI fan-out**: T009/T010/T011 can run in parallel after T008; T012 after T011

## Notes

- **1:1 file mapping**: T001–T006 each touch exactly one file (constitution DAG principle)
- **No new dev variables**: `vpc_id` and `vpc_cidr` already exist in the dev environment from 002
- **Deployment**: Stage 1–2 changes are applied by the existing `.github/workflows/terraform-apply.yml` on main push — no local apply
- **Verification**: Stage 3 tasks run in GitHub Actions CI only (constitution principles 5, 6, 8) — never locally
