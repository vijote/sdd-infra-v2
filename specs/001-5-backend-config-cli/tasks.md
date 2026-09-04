# Execution Graph (DAG): Backend Config CLI

**Input**: Design documents from `/specs/001-5-backend-config-cli/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`
- **[TaskID]**: Sequential zero-padded number (T001, T002, T003...)
- **[Stage]**: Architectural stage indicator (Stage 1: Terraform, Stage 2: Bootstrap, etc.)
- **Description**: Concrete action with exact file path
- **[Dependencies]**: Explicit preceding task IDs or omitted for root tasks

---

## Stage 1: Backend Configuration

- [x] T001 [Stage 1: Backend] Remove variable references from terraform backend block in `terraform/environments/dev/backend.tf` (Depends on none)

## Stage 2: Workflow Update

- [x] T002 [Stage 2: Workflow] Update terraform init with -backend-config arguments in `.github/workflows/terraform-apply.yml` (Depends on T001)

---

## Dependency & Execution Rules

- **Root Tasks**: T001 (no dependencies)
- **Sequential Execution**: T001 → T002 (backend config must be updated before workflow)
- **Acceptance Criteria Mapping**: T001 satisfies AC-001, AC-004; T002 satisfies AC-002, AC-003
- **Constitution Compliance**: No validation or verification steps per Section 6