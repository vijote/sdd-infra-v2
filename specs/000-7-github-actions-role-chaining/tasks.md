# Execution Graph (DAG): GitHub Actions Role Chaining

**Input**: Design documents from `/specs/000-7-github-actions-role-chaining/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`
- **[TaskID]**: Sequential ID (`T001`, `T002`, ...)
- **[Stage]**: Architectural stage (`[Stage 1: CloudFormation]`, `[Stage 2: Workflow]`, etc.)
- **Description & Path**: Exact 1:1 file edit, manifest, or command action with relative path
- **(Depends on ...)**: Preceding task IDs required before execution

---

## Stage 1: CloudFormation Update

- [x] T001 [Stage 1: CloudFormation] Add external ID condition to assume role trust policy in `cloudformation/github-oidc-roles.yaml`
- [x] T002 [Stage 1: CloudFormation] Update bootstrap role permission to reference external ID in `cloudformation/github-oidc-roles.yaml` (Depends on T001)
- [x] T003 [Stage 1: CloudFormation] Deploy CloudFormation stack with external ID support (`aws cloudformation deploy`) (Depends on T002)

---

## Stage 2: Workflow Migration - Terraform Apply

- [x] T004 [Stage 2: Workflows] Remove manual assume-role step in `.github/workflows/terraform-apply.yml` (Depends on T003)
- [x] T005 [Stage 2: Workflows] Add role-chaining parameter to aws-actions/configure-aws-credentials in `.github/workflows/terraform-apply.yml` (Depends on T004)
- [x] T006 [Stage 2: Workflows] Add role-external-id parameter to aws-actions/configure-aws-credentials in `.github/workflows/terraform-apply.yml` (Depends on T004)
- [x] T007 [Stage 2: Workflows] Add role-duration-seconds parameter to aws-actions/configure-aws-credentials in `.github/workflows/terraform-apply.yml` (Depends on T004)

---

## Stage 3: Workflow Migration - Terraform Destroy

- [x] T008 [Stage 3: Workflows] Remove manual assume-role step in `.github/workflows/terraform-destroy.yml` (Depends on T007)
- [x] T009 [Stage 3: Workflows] Add role-chaining parameter to aws-actions/configure-aws-credentials in `.github/workflows/terraform-destroy.yml` (Depends on T008)
- [x] T010 [Stage 3: Workflows] Add role-external-id parameter to aws-actions/configure-aws-credentials in `.github/workflows/terraform-destroy.yml` (Depends on T008)
- [x] T011 [Stage 3: Workflows] Add role-duration-seconds parameter to aws-actions/configure-aws-credentials in `.github/workflows/terraform-destroy.yml` (Depends on T008)

---

## Stage 4: Workflow Migration - Terraform Unlock

- [x] T012 [Stage 4: Workflows] Remove manual assume-role step in `.github/workflows/terraform-unlock.yml` (Depends on T011)
- [x] T013 [Stage 4: Workflows] Add role-chaining parameter to aws-actions/configure-aws-credentials in `.github/workflows/terraform-unlock.yml` (Depends on T012)
- [x] T014 [Stage 4: Workflows] Add role-external-id parameter to aws-actions/configure-aws-credentials in `.github/workflows/terraform-unlock.yml` (Depends on T012)
- [x] T015 [Stage 4: Workflows] Add role-duration-seconds parameter to aws-actions/configure-aws-credentials in `.github/workflows/terraform-unlock.yml` (Depends on T012)

---

## Stage 5: Validation & Acceptance

- [x] T016 [Stage 5: Validation] Verify role-chaining parameter exists in workflows (`grep -q "role-chaining: true" .github/workflows/*.yml`) (Depends on T015)
- [x] T017 [Stage 5: Validation] Verify role-external-id parameter exists in workflows (`grep -q "role-external-id" .github/workflows/*.yml`) (Depends on T015)
- [x] T018 [Stage 5: Validation] Verify no manual STS assume-role commands (`! grep -r "aws sts assume-role" .github/workflows/`) (Depends on T015)
- [x] T019 [Stage 5: Validation] Verify external ID condition in CloudFormation (`grep -A 5 "sts:ExternalId" cloudformation/github-oidc-roles.yaml`) (Depends on T003)
- [x] T020 [Stage 5: Validation] Verify role session duration configured (`grep -q "role-duration-seconds: 3600" .github/workflows/*.yml`) (Depends on T015)
- [x] T021 [Stage 5: Validation] Verify workflow env context maintained (`grep -q "env:" .github/workflows/terraform-apply.yml`) (Depends on T015)
- [x] T022 [Stage 5: Validation] Test role chaining execution in workflow (`aws sts get-caller-identity --query Arn --output text | grep -q assume`) (Depends on T020)

---

## Acceptance Criteria Mapping

- AC-001: Role chaining configuration validated by T016
- AC-002: External ID parameter validated by T017
- AC-003: No manual STS commands validated by T018
- AC-004: External ID condition validated by T019
- AC-005: Session duration validated by T020
- AC-006: Env context maintained validated by T021
- AC-007: Role chaining execution validated by T022

---

## Parallelization Opportunities

- T005, T006, T007 can be developed in parallel (role chaining parameters in terraform-apply.yml)
- T009, T010, T011 can be developed in parallel (role chaining parameters in terraform-destroy.yml)
- T013, T014, T015 can be developed in parallel (role chaining parameters in terraform-unlock.yml)
- T016, T017, T018, T020, T021 can be developed in parallel (workflow configuration validation)
- T019 can be developed in parallel with other validation tasks

---

## Dependency & Execution Rules
- Every task MUST correspond to a 1:1 file edit, specific command execution, or verification step.
- Tasks within the same Stage with no mutual dependencies can execute in parallel.
- Stage transitions require full completion of upstream dependencies.
- All validation tasks depend on workflow migrations completion to ensure configuration integrity.