# Execution Graph (DAG): CloudFormation Circular Dependency Fix

**Input**: Design documents from `/specs/000-8-cloudformation-circular-dependency-fix/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

## Format: `- [ ] [TaskID] [Stage] Description in [File Path] (Depends on [Dependencies])`
- **[TaskID]**: Sequential ID (`T001`, `T002`, ...)
- **[Stage]**: Architectural stage (`[Stage 1: CloudFormation]`, `[Stage 2: Validation]`, etc.)
- **Description & Path**: Exact 1:1 file edit, manifest, or command action with relative path
- **(Depends on ...)**: Preceding task IDs required before execution

---

## Stage 1: CloudFormation Update - BootstrapRole Policy

- [x] T001 [Stage 1: CloudFormation] Replace !GetAtt AssumeRole.Arn with !Ref AssumeRole in BootstrapRole policy Resource field in `cloudformation/github-oidc-roles.yaml`

---

## Stage 2: CloudFormation Update - AssumeRole Trust Policy

- [x] T002 [Stage 2: CloudFormation] Replace !GetAtt BootstrapRole.Arn with !Ref BootstrapRole in AssumeRole trust policy Principal field in `cloudformation/github-oidc-roles.yaml` (Depends on T001)

---

## Stage 3: CloudFormation Update - External ID Condition

- [x] T003 [Stage 3: CloudFormation] Replace !GetAtt AssumeRole.Arn with !Ref AssumeRole in external ID condition sts:ExternalId field in `cloudformation/github-oidc-roles.yaml` (Depends on T002)

---

## Stage 4: Validation & Acceptance

- [x] T004 [Stage 4: Validation] Validate CloudFormation template without circular dependency errors (`aws cloudformation validate-template --template-body file://cloudformation/github-oidc-roles.yaml`) (Depends on T003)
- [x] T005 [Stage 4: Validation] Verify no !GetAtt references between BootstrapRole and AssumeRole (`! grep -A 2 "Resource:" cloudformation/github-oidc-roles.yaml | grep "GetAtt"`) (Depends on T003)
- [x] T006 [Stage 4: Validation] Verify BootstrapRole uses !Ref AssumeRole in policy (`grep -q "Resource: !Ref AssumeRole" cloudformation/github-oidc-roles.yaml`) (Depends on T003)
- [x] T007 [Stage 4: Validation] Verify AssumeRole uses !Ref BootstrapRole in trust policy (`grep -q "AWS: !Ref BootstrapRole" cloudformation/github-oidc-roles.yaml`) (Depends on T003)
- [x] T008 [Stage 4: Validation] Verify external ID condition uses !Ref AssumeRole (`grep -q "sts:ExternalId: !Ref AssumeRole" cloudformation/github-oidc-roles.yaml`) (Depends on T003)
- [ ] T009 [Stage 4: Validation] Deploy CloudFormation stack successfully (`aws cloudformation deploy --stack-name github-oidc-roles --template-file cloudformation/github-oidc-roles.yaml --capabilities CAPABILITY_NAMED_IAM`) (Depends on T004) - *Requires AWS credentials*
- [ ] T010 [Stage 4: Validation] Verify role ARNs are properly exported (`aws cloudformation describe-stacks --stack-name github-oidc-roles --query "Stacks[0].Outputs" | grep -E "BootstrapRoleArn|AssumeRoleArn"`) (Depends on T009) - *Requires AWS credentials*

---

## Stage 5: GitHub Configuration

- [ ] T011 [Stage 5: GitHub] Update GitHub repository variable AWS_BOOTSTRAP_ROLE_ARN with new role ARN from CloudFormation outputs (Depends on T010) - *Requires AWS deployment completion*
- [ ] T012 [Stage 5: GitHub] Update GitHub repository variable AWS_ASSUME_ROLE_ARN with new role ARN from CloudFormation outputs (Depends on T010) - *Requires AWS deployment completion*

---

## Acceptance Criteria Mapping

- AC-001: CloudFormation validation without circular dependency errors validated by T004
- AC-002: No !GetAtt references validated by T005
- AC-003: BootstrapRole !Ref usage validated by T006
- AC-004: AssumeRole !Ref usage validated by T007
- AC-005: External ID !Ref usage validated by T008
- AC-006: CloudFormation deployment validated by T009
- AC-007: Role ARN exports validated by T010

---

## Parallelization Opportunities

- T006, T007, T008 can be developed in parallel (reference verification checks)
- T011, T012 can be developed in parallel (GitHub repository variable updates)
- T005 can be developed in parallel with T006, T007, T008 (validation checks)

---

## Dependency & Execution Rules

- Every task MUST correspond to a 1:1 file edit, specific command execution, or verification step.
- Tasks within the same Stage with no mutual dependencies can execute in parallel.
- Stage transitions require full completion of upstream dependencies.
- All validation tasks depend on CloudFormation updates completion to ensure configuration integrity.
- GitHub configuration tasks depend on successful deployment and output verification.