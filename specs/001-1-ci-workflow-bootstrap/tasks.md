# Execution Graph (DAG): CI Workflow Bootstrap

**Input**: Design documents from `/specs/001-1-ci-workflow-bootstrap/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`
- **[TaskID]**: Sequential ID (`T001`, `T002`, ...)
- **[Stage]**: Architectural stage (`[Stage 1: Variables]`, `[Stage 2: Workflow]`, etc.)
- **Description & Path**: Exact 1:1 file creation or edit action with relative path
- **(Depends on ...)**: Preceding task IDs required before execution

---

## Stage 1: GitHub Variables Configuration

- [x] T001 [Stage 1: Variables] Create AWS_REGION repository variable in GitHub Settings (Depends on none)
- [x] T002 [Stage 1: Variables] Create AWS_BOOTSTRAP_ROLE_ARN repository variable in GitHub Settings (Depends on T001)
- [x] T003 [Stage 1: Variables] Create AWS_TERRAFORM_ROLE repository variable in GitHub Settings (Depends on T001)
- [x] T004 [Stage 1: Variables] Create TF_VAR_state_bucket_name repository variable in GitHub Settings (Depends on T001)

---

## Stage 2: Workflow Update

- [x] T005 [Stage 2: Workflow] Update workflow triggers and environment variables in `.github/workflows/terraform-apply.yml` (Depends on T001, T002, T003, T004)
- [x] T006 [Stage 2: Workflow] Update AWS credentials configuration with role chaining in `.github/workflows/terraform-apply.yml` (Depends on T005)
- [x] T007 [Stage 2: Workflow] Update Terraform apply step with proper directory and variables in `.github/workflows/terraform-apply.yml` (Depends on T005)
- [x] T008 [Stage 2: Workflow] Remove all validation steps from `.github/workflows/terraform-apply.yml` (Depends on T005)

---

## Stage 3: Workflow Testing

- [x] T009 [Stage 3: Testing] Manual workflow dispatch to verify role chaining and Terraform apply execution (Depends on T005, T006, T007, T008)

---

## Dependency & Execution Rules
- Every task MUST correspond to a 1:1 file creation or edit action.
- Tasks within the same Stage with no mutual dependencies can execute in parallel.
- Stage transitions require full completion of upstream dependencies.
- All validation and testing is handled personally by the user.