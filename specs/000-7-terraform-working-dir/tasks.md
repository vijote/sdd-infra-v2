# Execution Graph (DAG): Terraform Working Directory Fix

**Input**: Design documents from `/specs/000-7-terraform-working-dir/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`
- **[TaskID]**: Sequential ID (`T001`, `T002`, ...)
- **[Stage]**: Architectural stage (`[Stage 1: Workflow]`, `[Stage 2: Validation]`, etc.)
- **Description & Path**: Exact 1:1 file edit, manifest, or command action with relative path
- **(Depends on ...)**: Preceding task IDs required before execution

---

## Stage 1: Working Directory Configuration

- [x] T001 [Stage 1: Workflow] Add working-directory parameter to Terraform Format Check step in `.github/workflows/terraform-apply.yml`
- [x] T002 [Stage 1: Workflow] Add working-directory parameter to Terraform Init step in `.github/workflows/terraform-apply.yml` (Depends on T001)
- [x] T003 [Stage 1: Workflow] Add working-directory parameter to Terraform Validate step in `.github/workflows/terraform-apply.yml` (Depends on T002)
- [x] T004 [Stage 1: Workflow] Add working-directory parameter to Terraform Plan step in `.github/workflows/terraform-apply.yml` (Depends on T003)
- [x] T005 [Stage 1: Workflow] Add working-directory parameter to Terraform Apply step in `.github/workflows/terraform-apply.yml` (Depends on T004)

---

## Stage 2: Validation & Acceptance Testing

- [x] T006 [Stage 2: Validation] Verify terraform init executes successfully from working directory (`cd terraform && terraform init` returns exit code 0) (Depends on T005)
- [x] T007 [Stage 2: Validation] Verify terraform plan generates expected resources from working directory (`cd terraform && terraform plan -out=tfplan` returns exit code 0) (Depends on T005)
- [x] T008 [Stage 2: Validation] Verify terraform show JSON conversion succeeds in working directory (`cd terraform && terraform show -json tfplan > plan.json` returns exit code 0) (Depends on T005)
- [x] T009 [Stage 2: Validation] Verify terraform apply executes successfully from working directory (`cd terraform && terraform apply -auto-approve tfplan` executes without errors) (Depends on T005)
- [x] T010 [Stage 2: Validation] Verify GitHub Actions workflow steps complete with working-directory parameter (workflow log shows all Terraform steps with exit code 0) (Depends on T005)
- [x] T011 [Stage 2: Validation] Verify module sources resolve correctly from working directory (no "module not found" errors) (Depends on T005)
- [x] T012 [Stage 2: Validation] Verify state file and plan files generated in correct directory (`terraform/` directory contains expected files) (Depends on T005)

---

## Dependency & Execution Rules
- Every task MUST correspond to a 1:1 file creation, edit, or specific verification command.
- Tasks within the same Stage with no mutual dependencies can execute in parallel.
- Stage transitions require full completion of upstream dependencies.