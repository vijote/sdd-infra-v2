# Execution Graph (DAG): CI/CD Foundation Integration

**Input**: Design documents from `/specs/000-9-cicd-foundation-integration/`
**Prerequisites**: plan.md (Architecture Delta & File Impact Matrix), spec.md (Contracts & Acceptance Criteria)

---

## Stage 1: CloudFormation Split & Bootstrap Role

- [ ] T001 [Stage 1: CloudFormation] Split `cloudformation/github-oidc-roles.yaml` into bootstrap role only template with OIDC trust relationship
- [ ] T002 [Stage 1: CloudFormation] Add CloudFormation validation step to GitHub Actions workflow for bootstrap role template (Depends on T001)
- [ ] T003 [Stage 1: CloudFormation] Add CloudFormation deployment step to GitHub Actions workflow for bootstrap role stack (Depends on T002)
- [ ] T004 [Stage 1: Validation] Add deployment status verification step to GitHub Actions workflow for bootstrap role stack (Depends on T003)

## Stage 2: Assume Role Stack

- [ ] T005 [Stage 2: CloudFormation] Split `cloudformation/github-oidc-roles.yaml` into assume role template with role chaining and external ID validation (Depends on T004)
- [ ] T006 [Stage 2: CloudFormation] Add CloudFormation validation step to GitHub Actions workflow for assume role template (Depends on T005)
- [ ] T007 [Stage 2: CloudFormation] Add CloudFormation deployment step to GitHub Actions workflow for assume role stack (Depends on T006)
- [ ] T008 [Stage 2: Validation] Add deployment status verification step to GitHub Actions workflow for assume role stack (Depends on T007)

## Stage 3: GitHub Repository Variables

- [ ] T009 [Stage 3: GitHub] Configure GitHub repository variable AWS_BOOTSTRAP_ROLE_ARN with bootstrap role ARN from CloudFormation outputs (Depends on T004)
- [ ] T010 [Stage 3: GitHub] Configure GitHub repository variable AWS_ASSUME_ROLE_ARN with assume role ARN from CloudFormation outputs (Depends on T008)
- [ ] T011 [Stage 3: GitHub] Configure GitHub repository variable AWS_REGION with target AWS region (Depends on T010)
- [ ] T012 [Stage 3: Validation] Add repository variables access verification step to GitHub Actions workflow (Depends on T011)

## Stage 4: GitHub Actions Workflow Updates

- [ ] T013 [Stage 4: GitHub Actions] Update `.github/workflows/terraform-apply.yml` with OIDC authentication and role chaining configuration (Depends on T012)
- [ ] T014 [Stage 4: GitHub Actions] Update `.github/workflows/terraform-destroy.yml` with OIDC authentication and role chaining configuration (Depends on T013)
- [ ] T015 [Stage 4: GitHub Actions] Update `.github/workflows/terraform-unlock.yml` with OIDC authentication and role chaining configuration (Depends on T014)
- [ ] T016 [Stage 4: Validation] Add OIDC permissions verification step to GitHub Actions workflow (Depends on T015)

## Stage 5: Integration Validation & Acceptance

- [ ] T017 [Stage 5: Validation] Add CloudFormation exports verification step to GitHub Actions workflow (Depends on T008)
- [ ] T018 [Stage 5: Validation] Add role chaining authentication test step to GitHub Actions workflow (Depends on T017)
- [ ] T019 [Stage 5: Validation] Add GitHub Actions workflow execution success verification step (Depends on T018)
- [ ] T020 [Stage 5: Documentation] Create `specs/000-9-cicd-foundation-integration/required-names.md` with required names and variables documentation (Depends on T019)