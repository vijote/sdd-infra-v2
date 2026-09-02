# CI/CD Workflows Spec

**Purpose**: Complete GitHub Actions CI/CD pipeline for automated Terraform infrastructure deployment with OIDC authentication.

## Scope
- GitHub Actions workflows for Terraform apply/destroy operations
- OIDC authentication with AWS role assumption
- Centralized state management with S3 backend
- Automated deployment on main branch push
- Post-deployment validation and output reporting

## Key Files
- `spec.md` - Technical specification with infrastructure contracts and acceptance criteria
- `plan.md` - Architecture delta and file impact matrix
- `tasks.md` - 12 dependency-ordered implementation tasks (all completed)
- `checklists/requirements.md` - Technical quality checklist (18 checks)
- `validate.sh` - Post-deployment validation script

## Main Components
1. **Workflow Setup**: GitHub Actions workflows with OIDC auth and environment protection
2. **State Backend**: S3 bucket with DynamoDB locking for centralized state management
3. **Validation Gate**: Terraform validation, planning, and artifact storage
4. **Apply Execution**: Single workflow run applying all infrastructure phases (001-005)
5. **Post-Validation**: Automated validation scripts and output reporting

## Dependencies
- Requires AWS OIDC roles to be pre-provisioned
- Depends on specs 001-005 for infrastructure phases
- Uses Terraform >=1.5.0 and GitHub Actions runners

## Quick Reference
- **Status**: Draft, all tasks completed
- **Acceptance Criteria**: 7 machine-verifiable criteria
- **Verification Gates**: 6 validation commands
- **Key Contract**: Single terraform apply across all phases with OIDC authentication