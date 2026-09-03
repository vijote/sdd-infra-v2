# Execution Graph (DAG): CloudFormation Circular Dependency Fix

**Input**: Design documents from `/specs/000-8-cloudformation-circular-dependency-fix/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`
- **[TaskID]**: Sequential ID (`T001`, `T002`, ...)
- **[Stage]**: Architectural stage (`[Stage 1: Bootstrap Stack]`, `[Stage 2: Assume Stack]`, etc.)
- **Description & Path**: Exact 1:1 file edit, manifest, or command action with relative path
- **(Depends on ...)**: Preceding task IDs required before execution

---

## Stage 1: Bootstrap Stack Creation

- [x] T001 [Stage 1: Bootstrap Stack] Create `cloudformation/bootstrap-role.yaml` with BootstrapRole, OIDC trust, and BootstrapRoleArn output

---

## Stage 2: Bootstrap Stack Deployment

- [ ] T002 [Stage 2: Bootstrap Stack] Validate bootstrap stack template (`aws cloudformation validate-template --template-body file://cloudformation/bootstrap-role.yaml`) (Depends on T001) - *Requires AWS credentials*
- [ ] T003 [Stage 2: Bootstrap Stack] Deploy bootstrap stack (`aws cloudformation deploy --stack-name github-oidc-bootstrap-role --template-file cloudformation/bootstrap-role.yaml --capabilities CAPABILITY_NAMED_IAM`) (Depends on T002) - *Requires AWS credentials*
- [ ] T004 [Stage 2: Bootstrap Stack] Extract BootstrapRoleArn from stack outputs (`aws cloudformation describe-stacks --stack-name github-oidc-bootstrap-role --query "Stacks[0].Outputs[?OutputKey=='BootstrapRoleArn'].OutputValue" --output text`) (Depends on T003) - *Requires AWS deployment completion*

---

## Stage 3: Assume Stack Creation

- [x] T005 [Stage 3: Assume Stack] Create `cloudformation/assume-role.yaml` with AssumeRole, BootstrapRoleArn parameter, and AssumeRoleArn output (Depends on T004)

---

## Stage 4: Assume Stack Deployment

- [ ] T006 [Stage 4: Assume Stack] Validate assume stack template (`aws cloudformation validate-template --template-body file://cloudformation/assume-role.yaml`) (Depends on T005) - *Requires AWS credentials*
- [ ] T007 [Stage 4: Assume Stack] Deploy assume stack with BootstrapRoleArn parameter (`aws cloudformation deploy --stack-name github-oidc-assume-role --template-file cloudformation/assume-role.yaml --parameter-overrides BootstrapRoleArn=<ARN> --capabilities CAPABILITY_NAMED_IAM`) (Depends on T006) - *Requires AWS credentials and BootstrapRoleArn from T004*
- [ ] T008 [Stage 4: Assume Stack] Extract AssumeRoleArn from stack outputs (`aws cloudformation describe-stacks --stack-name github-oidc-assume-role --query "Stacks[0].Outputs[?OutputKey=='AssumeRoleArn'].OutputValue" --output text`) (Depends on T007) - *Requires AWS deployment completion*

---

## Stage 5: Cleanup

- [x] T009 [Stage 5: Cleanup] Remove old circular dependency template (`rm cloudformation/github-oidc-roles.yaml`) (Depends on T008)

---

## Stage 6: GitHub Configuration

- [ ] T010 [Stage 6: GitHub] Update GitHub repository variable AWS_BOOTSTRAP_ROLE_ARN with BootstrapRoleArn from T004 (Depends on T004)
- [ ] T011 [Stage 6: GitHub] Update GitHub repository variable AWS_ASSUME_ROLE_ARN with AssumeRoleArn from T008 (Depends on T008)

---

## Acceptance Criteria Mapping

- AC-001: Bootstrap stack validation validated by T002
- AC-002: Assume stack validation validated by T006
- AC-003: Bootstrap stack deployment validated by T003
- AC-004: Bootstrap stack outputs validated by T004
- AC-005: Assume stack deployment validated by T007
- AC-006: Assume stack outputs validated by T008
- AC-007: Both role ARNs accessible for GitHub Actions validated by T010, T011

---

## Parallelization Opportunities

- T010, T011 can be developed in parallel (GitHub repository variable updates)
- T002 can be developed in parallel with T005 (validation checks for different stacks)

---

## Dependency & Execution Rules

- Every task MUST correspond to a 1:1 file edit, specific command execution, or verification step.
- Sequential deployment is mandatory: Bootstrap stack (T001-T004) must complete before Assume stack (T005-T008).
- Parameter passing: T004 output (BootstrapRoleArn) is required for T007 deployment.
- GitHub configuration tasks (T010, T011) depend on their respective stack outputs.
- Cleanup task (T009) depends on successful Assume stack deployment completion.