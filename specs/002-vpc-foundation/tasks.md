# Execution Graph (DAG): VPC Foundation

**Input**: Design documents from `/specs/002-vpc-foundation/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`
- **[TaskID]**: Sequential ID (`T001`, `T002`, ...)
- **[Stage]**: Architectural stage (`[Stage 1: VPC Module]`, `[Stage 2: Dev Env]`, etc.)
- **Description & Path**: Exact 1:1 file edit, manifest, or command action with relative path
- **(Depends on ...)**: Preceding task IDs required before execution

**Execution scope**: T001–T007 are agent-executable file edits. T008–T014 are CI-only verification gates executed in GitHub Actions (never locally by the agent) — see constitution Principles 5, 6 & 8.

---

## Stage 1: VPC Module

- [x] T001 [Stage 1: VPC Module] Declare Terraform >= 1.5.0, AWS provider >= 5.0.0, and provider config in `terraform/modules/vpc/versions.tf`
- [x] T002 [Stage 1: VPC Module] Define input variables (region, vpc_cidr, availability_zones, tags) in `terraform/modules/vpc/variables.tf`
- [x] T003 [Stage 1: VPC Module] Implement VPC, 3 public + 3 private subnets, IGW, single NAT GW (public subnet 1), EIP, 2 route tables, 6 associations in `terraform/modules/vpc/main.tf` (Depends on T001, T002)
- [x] T004 [Stage 1: VPC Module] Export outputs (vpc_id, public_subnet_ids, private_subnet_ids, nat_gateway_id) in `terraform/modules/vpc/outputs.tf` (Depends on T003)

---

## Stage 2: Dev Environment Wiring

- [x] T005 [Stage 2: Dev Env] Add input variables vpc_cidr (default `10.0.0.0/16`) and availability_zones (default 3 AZs) in `terraform/environments/dev/variables.tf`
- [x] T006 [Stage 2: Dev Env] Add `module "vpc"` instantiation (source `../../modules/vpc`) in `terraform/environments/dev/main.tf` (Depends on T004, T005)
- [x] T007 [Stage 2: Dev Env] Create root outputs (vpc_id, private_subnet_ids) for downstream phases in `terraform/environments/dev/outputs.tf` (Depends on T006)

---

## Stage 3: Verification (CI-only — executed in GitHub Actions, never locally)

- [x] T008 [Stage 3: Verification] Run IaC validation (`terraform fmt -check -recursive && terraform validate`) in CI (Depends on T007) — AC-001
- [x] T009 [Stage 3: Verification] Run `terraform plan -detailed-exitcode` in CI (Depends on T008) — AC-002
- [x] T010 [Stage 3: Verification] Verify VPC CIDR = `10.0.0.0/16` via `aws ec2 describe-vpcs` in CI (Depends on T009) — AC-003
- [x] T011 [Stage 3: Verification] Verify 6 subnets (3 public + 3 private) via `aws ec2 describe-subnets` in CI (Depends on T009) — AC-004
- [x] T012 [Stage 3: Verification] Verify IGW attached via `aws ec2 describe-internet-gateways` in CI (Depends on T009) — AC-005
- [x] T013 [Stage 3: Verification] Verify single NAT Gateway via `aws ec2 describe-nat-gateways` in CI (Depends on T009) — AC-006
- [x] T014 [Stage 3: Verification] Verify 3 route tables via `aws ec2 describe-route-tables` in CI (Depends on T009) — AC-007

---

## Acceptance Criteria Mapping

- AC-001: Terraform syntax & formatting — validated by T008
- AC-002: Terraform plan generates expected resources — validated by T009
- AC-003: VPC CIDR correct — validated by T010
- AC-004: 6 subnets created — validated by T011
- AC-005: Internet Gateway attached — validated by T012
- AC-006: NAT Gateway created — validated by T013
- AC-007: Route tables created — validated by T014

---

## Parallelization Opportunities

- T001 and T002 are independent root tasks (versions + variables) — can run in parallel
- T005 is independent of Stage 1 (dev env variables) — can run in parallel with T001–T004
- T010–T014 are independent of each other (separate AWS CLI checks) — can run in parallel after T009

---

## Dependency & Execution Rules

- Every task MUST correspond to a 1:1 file creation, edit, or specific verification command.
- Tasks within the same Stage with no mutual dependencies can execute in parallel.
- Stage transitions require full completion of upstream dependencies.
- **Agent scope**: T001–T007 (file edits only). The agent does NOT run `terraform plan`, `aws ec2`, or any AWS CLI command locally.
- **CI scope**: T008–T014 execute in the GitHub Actions workflow (`.github/workflows/terraform-apply.yml` for apply; verification gates run in CI). No local tooling, no manual intervention (constitution Principles 5, 6 & 8).
