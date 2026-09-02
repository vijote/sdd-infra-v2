# Execution Graph (DAG): Terraform Workflow Fix

**Input**: Design documents from `/specs/000-6-terraform-workflow-fix/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`
- **[TaskID]**: Sequential ID (`T001`, `T002`, ...)
- **[Stage]**: Architectural stage (`[Stage 1: Workflow]`, `[Stage 2: Validation]`, etc.)
- **Description & Path**: Exact 1:1 file edit, manifest, or command action with relative path
- **(Depends on ...)**: Preceding task IDs required before execution

---

## Stage 1: Workflow Fix

- [x] T001 [Stage 1: Workflow] Modify terraform plan command in `.github/workflows/terraform-apply.yml` to separate binary plan generation from JSON conversion

---

## Stage 2: Validation & Acceptance Testing

- [x] T002 [Stage 2: Validation] Verify terraform plan command executes without syntax errors (`terraform plan -out=tfplan` returns exit code 0) (Depends on T001)
- [x] T003 [Stage 2: Validation] Verify terraform show JSON conversion succeeds (`terraform show -json tfplan > plan.json` returns exit code 0) (Depends on T001)
- [x] T004 [Stage 2: Validation] Verify jq processing extracts resource modes successfully (`jq -r '.configuration.root_module.resources | map(.mode) | unique | join(",")' plan.json` returns valid output) (Depends on T001)
- [x] T005 [Stage 2: Validation] Verify binary plan file is valid for apply execution (`terraform apply -auto-approve tfplan` executes without errors) (Depends on T001)
- [x] T006 [Stage 2: Validation] Verify GitHub Actions workflow step completes successfully (workflow log shows "Terraform Plan" step with exit code 0) (Depends on T001)
- [x] T007 [Stage 2: Validation] Verify phase detection output is properly set (`echo "phases=$phases" >> $GITHUB_OUTPUT` writes to GitHub Actions output) (Depends on T001)

---

## Dependency & Execution Rules
- Every task MUST correspond to a 1:1 file creation, edit, or specific verification command.
- Tasks within the same Stage with no mutual dependencies can execute in parallel.
- Stage transitions require full completion of upstream dependencies.