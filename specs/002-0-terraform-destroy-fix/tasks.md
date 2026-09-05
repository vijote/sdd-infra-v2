# Execution Graph (DAG): Terraform Destroy Workflow Fix

**Input**: Design documents from `/specs/002-0-terraform-destroy-fix/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`
- **[TaskID]**: Sequential ID (`T001`, `T002`, ...)
- **[Stage]**: Architectural stage (`[Stage 1: Workflow]`, `[Stage 2: Verification]`, etc.)
- **Description & Path**: Exact 1:1 file edit or command action with relative path
- **(Depends on ...)**: Preceding task IDs required before execution

**Execution scope**: T001 is the agent-executable file edit. T002–T008 are CI-only verification gates executed in GitHub Actions (never locally by the agent) — see constitution Principles 5, 6 & 8.

---

## Stage 1: Workflow Correction

- [x] T001 [Stage 1: Workflow] Correct `.github/workflows/terraform-destroy.yml`: add `cd terraform/environments/dev` to init/destroy steps, add `-backend-config="bucket=…"` + `-backend-config="region=…"` to `terraform init`, replace single-step auth with 2-step role chain (bootstrap OIDC → assume role, `role-chaining: true`, remove `role-external-id`), add `TF_VAR_state_bucket_name`, remove `TF_VAR_github_owner`/`TF_VAR_github_repo`/`TF_VAR_mysql_root_password`/`TF_VAR_mysql_password`, retain `workflow_dispatch` + type-"destroy" confirmation gate

---

## Stage 2: Verification (CI-only — executed in GitHub Actions, never locally)

- [x] T002 [Stage 2: Verification] Lint workflow YAML (`actionlint .github/workflows/terraform-destroy.yml`) in CI (Depends on T001) — AC-001
- [x] T003 [Stage 2: Verification] Verify `-backend-config="bucket=` present in CI (Depends on T001) — AC-002
- [x] T004 [Stage 2: Verification] Verify `cd terraform/environments/dev` present in CI (Depends on T001) — AC-003
- [x] T005 [Stage 2: Verification] Verify `role-chaining: true` present AND `role-external-id` absent in CI (Depends on T001) — AC-004
- [x] T006 [Stage 2: Verification] Verify `TF_VAR_state_bucket_name` present in CI (Depends on T001) — AC-005
- [x] T007 [Stage 2: Verification] Verify stale vars (`TF_VAR_mysql_root_password`, `TF_VAR_mysql_password`, `TF_VAR_github_owner`, `TF_VAR_github_repo`) all absent in CI (Depends on T001) — AC-006
- [x] T008 [Stage 2: Verification] Verify `github.event.inputs.confirm` gate retained in CI (Depends on T001) — AC-007

---

## Acceptance Criteria Mapping

- AC-001: Workflow YAML valid — validated by T002
- AC-002: Backend config present — validated by T003
- AC-003: Working directory set — validated by T004
- AC-004: 2-step role chain, no external-id — validated by T005
- AC-005: State bucket var present — validated by T006
- AC-006: No stale vars — validated by T007
- AC-007: Confirmation gate retained — validated by T008

---

## Parallelization Opportunities

- T002–T008 are independent of each other (separate lint/grep checks) — can run in parallel after T001

---

## Dependency & Execution Rules

- Every task MUST correspond to a 1:1 file creation, edit, or specific verification command.
- Tasks within the same Stage with no mutual dependencies can execute in parallel.
- Stage transitions require full completion of upstream dependencies.
- **Agent scope**: T001 (single file edit only). The agent does NOT run `actionlint`, `grep`, or any AWS CLI command locally.
- **CI scope**: T002–T008 execute in the GitHub Actions workflow. No local tooling, no manual intervention (constitution Principles 5, 6 & 8).
