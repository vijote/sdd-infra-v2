# Tasks: CI/CD Workflows

**Branch**: `000-0-cicd-workflows` | **Date**: 2026-09-01 | **Total Tasks**: 12

## Stage 1: Workflow Setup & OIDC Authentication

- [x] T001 [Stage 1: GitHub Actions] Create main terraform-apply.yml workflow with OIDC authentication in .github/workflows/terraform-apply.yml
- [x] T002 [Stage 1: GitHub Actions] Create terraform-destroy.yml workflow with confirmation gate in .github/workflows/terraform-destroy.yml (Depends on T001)
- [x] T003 [Stage 1: GitHub Actions] Create terraform-unlock.yml workflow for state recovery in .github/workflows/terraform-unlock.yml (Depends on T001)

## Stage 2: State Backend Configuration

- [x] T004 [Stage 2: Terraform Backend] Configure S3 backend with S3 native locking in terraform/backend.tf
- [x] T005 [Stage 2: Terraform Variables] Add GitHub OIDC role ARN and state configuration variables in terraform/variables.tf (Depends on T004)
- [x] T006 [Stage 2: Terraform Root] Update root module to include all phase dependencies in terraform/main.tf (Depends on T005)

## Stage 3: Validation & Planning

- [x] T007 [Stage 3: Validation] Add terraform fmt, validate, and plan steps to terraform-apply.yml workflow (Depends on T003)
- [x] T008 [Stage 3: Artifacts] Configure artifact storage for terraform plans in terraform-apply.yml workflow (Depends on T007)

## Stage 4: Apply Execution & Security

- [x] T009 [Stage 4: Apply Job] Configure apply job with AWS credentials and secret injection in terraform-apply.yml (Depends on T008)
- [x] T010 [Stage 4: Automated Deployment] Configure automated deployment on main branch push in terraform-apply.yml workflow (Depends on T009)

## Stage 5: Post-Validation & Acceptance

- [x] T011 [Stage 5: Validation Script] Create automated validation script for post-deployment checks in specs/000-0-cicd-workflows/validate.sh (Depends on T010)
- [x] T012 [Stage 5: Output Reporting] Add output reporting and summary steps to terraform-apply.yml workflow (Depends on T011)

## Acceptance Criteria Mapping

- AC-001: Workflow triggers validated by T001, T007, T009
- AC-002: Single run execution validated by T006, T009
- AC-003: State locking validated by T004, T009
- AC-004: Destroy confirmation validated by T002
- AC-005: State unlock validated by T003
- AC-006: Plan artifacts validated by T008
- AC-007: Secret injection validated by T009

## Parallelization Opportunities

- T001, T002, T003 can be developed in parallel (workflow creation)
- T004, T005, T006 have sequential dependencies (backend → variables → root)
- T007, T008 can be developed in parallel (validation and artifacts)
- T009, T010 have sequential dependencies (apply → environment protection)
- T011, T012 have sequential dependencies (script → reporting)