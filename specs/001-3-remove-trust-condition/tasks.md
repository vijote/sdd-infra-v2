# Execution Graph (DAG): Remove Trust Condition from Assume Role

**Input**: Design documents from `/specs/001-3-remove-trust-condition/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`
- **[TaskID]**: Sequential ID (`T001`, `T002`, ...)
- **[Stage]**: Architectural stage (`[Stage 1: CloudFormation]`, `[Stage 2: Testing]`, etc.)
- **Description & Path**: Exact 1:1 file creation or edit action with relative path
- **(Depends on ...)**: Preceding task IDs required before execution

---

## Stage 1: CloudFormation Update

- [x] T001 [Stage 1: CloudFormation] Remove Condition block from AssumeRolePolicyDocument in `cloudformation/assume-role.yaml` (Depends on none)

---

## Stage 2: Role Testing

- [x] T002 [Stage 2: Testing] Manual verification that GitHub Actions can assume role with session tags (Depends on T001)

---

## Dependency & Execution Rules
- Every task MUST correspond to a 1:1 file creation or edit action.
- Tasks within the same Stage with no mutual dependencies can execute in parallel.
- Stage transitions require full completion of upstream dependencies.
- All validation and testing is handled personally by the user.