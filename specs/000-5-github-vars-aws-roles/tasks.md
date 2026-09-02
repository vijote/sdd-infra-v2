# Execution Graph (DAG): GitHub Variables & AWS Role Chaining

**Input**: Design documents from `/specs/000-5-github-vars-aws-roles/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`
- **[TaskID]**: Sequential ID (`T001`, `T002`, ...)
- **[Stage]**: Architectural stage (`[Stage 1: CloudFormation]`, `[Stage 2: Variables]`, etc.)
- **Description & Path**: Exact 1:1 file edit, manifest, or command action with relative path
- **(Depends on ...)**: Preceding task IDs required before execution

---

## Stage 1: CloudFormation Deployment

- [x] T001 [Stage 1: CloudFormation] Create AWS IAM bootstrap role with OIDC trust in `cloudformation/github-oidc-roles.yaml`
- [x] T002 [Stage 1: CloudFormation] Create AWS IAM assume role with infrastructure permissions in `cloudformation/github-oidc-roles.yaml` (Depends on T001)
- [x] T003 [Stage 1: CloudFormation] Configure OIDC trust relationship for GitHub Actions in `cloudformation/github-oidc-roles.yaml` (Depends on T001)
- [x] T004 [Stage 1: CloudFormation] Deploy CloudFormation stack to create IAM roles (`aws cloudformation deploy`) (Depends on T002, T003)

---

## Stage 2: Repository Variables Setup

- [x] T005 [Stage 2: Variables] Create setup instructions for GitHub repository variables in `specs/000-5-github-vars-aws-roles/setup-instructions.md` (Depends on T004)
- [x] T006 [Stage 2: Variables] Document AWS_BOOTSTRAP_ROLE_ARN variable setup in `specs/000-5-github-vars-aws-roles/setup-instructions.md` (Depends on T005)
- [x] T007 [Stage 2: Variables] Document AWS_ASSUME_ROLE_ARN variable setup in `specs/000-5-github-vars-aws-roles/setup-instructions.md` (Depends on T005)
- [x] T008 [Stage 2: Variables] Document AWS_REGION variable setup in `specs/000-5-github-vars-aws-roles/setup-instructions.md` (Depends on T005)
- [x] T009 [Stage 2: Variables] Update README.md with GitHub variables setup section (Depends on T005)

---

## Stage 3: Workflow Updates

- [x] T010 [Stage 3: Workflows] Add env context for repository variables in `.github/workflows/terraform-apply.yml` (Depends on T009)
- [x] T011 [Stage 3: Workflows] Add env context for repository variables in `.github/workflows/terraform-destroy.yml` (Depends on T010)
- [x] T012 [Stage 3: Workflows] Add env context for repository variables in `.github/workflows/terraform-unlock.yml` (Depends on T010)

---

## Stage 4: Role Chaining Implementation

- [x] T013 [Stage 4: Role Chaining] Add bootstrap role assumption step in `.github/workflows/terraform-apply.yml` (Depends on T012)
- [x] T014 [Stage 4: Role Chaining] Add target role assumption step in `.github/workflows/terraform-apply.yml` (Depends on T013)
- [x] T015 [Stage 4: Role Chaining] Add bootstrap role assumption step in `.github/workflows/terraform-destroy.yml` (Depends on T011)
- [x] T016 [Stage 4: Role Chaining] Add target role assumption step in `.github/workflows/terraform-destroy.yml` (Depends on T015)
- [x] T017 [Stage 4: Role Chaining] Add bootstrap role assumption step in `.github/workflows/terraform-unlock.yml` (Depends on T012)
- [x] T018 [Stage 4: Role Chaining] Add target role assumption step in `.github/workflows/terraform-unlock.yml` (Depends on T017)

---

## Stage 5: Validation & Acceptance

- [x] T019 [Stage 5: Validation] Test repository variables access (`echo $AWS_REGION | grep -q "us-"`) (Depends on T018)
- [x] T020 [Stage 5: Validation] Test bootstrap role assumption (`aws sts get-caller-identity --query Arn --output text | grep -q bootstrap`) (Depends on T019)
- [x] T021 [Stage 5: Validation] Test target role assumption (`aws sts get-caller-identity --query Arn --output text | grep -q assume`) (Depends on T020)
- [x] T022 [Stage 5: Validation] Test role chaining credentials (`aws s3 ls s3://sdd-k8s-platform-terraform-state`) (Depends on T021)
- [x] T023 [Stage 5: Validation] Verify workflow env context (`grep -q "env:" .github/workflows/terraform-apply.yml`) (Depends on T018)
- [x] T024 [Stage 5: Validation] Verify no hardcoded regions (`! grep -r "us-east-1" .github/workflows/`) (Depends on T018)
- [x] T025 [Stage 5: Validation] Verify bootstrap role minimal permissions (`aws iam get-role-policy --role-name bootstrap-role --policy-name bootstrap-policy --query 'PolicyDocument.Statement[0].Action' --output text | grep -q "sts:AssumeRole"`) (Depends on T022)

---

## Acceptance Criteria Mapping

- AC-001: Repository variables accessible validated by T019
- AC-002: Bootstrap role assumption validated by T020
- AC-003: Target role assumption validated by T021
- AC-004: Role chaining credentials validated by T022
- AC-005: Workflow uses env context validated by T023
- AC-006: No hardcoded region validated by T024
- AC-007: Bootstrap role minimal permissions validated by T025

---

## Parallelization Opportunities

- T001, T002, T003 can be developed in parallel (CloudFormation role definitions)
- T006, T007, T008 can be developed in parallel (setup instructions sections)
- T011, T012 can be developed in parallel (workflow env context updates)
- T015, T017 can be developed in parallel (bootstrap role steps in different workflows)
- T016, T018 can be developed in parallel (target role steps in different workflows)
- T023, T024 can be developed in parallel (workflow configuration validation)

---

## Dependency & Execution Rules
- Every task MUST correspond to a 1:1 file creation, edit, or specific verification command.
- Tasks within the same Stage with no mutual dependencies can execute in parallel.
- Stage transitions require full completion of upstream dependencies.
