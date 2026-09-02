# Terraform Workflow Fix Spec

**Purpose**: Fix GitHub Actions workflow for proper Terraform plan processing and binary plan file handling.

## Scope
- GitHub Actions workflow configuration fix
- Terraform CLI execution and plan file handling
- Binary plan file generation and JSON conversion
- Phase detection via jq processing
- Artifact storage and apply execution

## Key Files
- `spec.md` - Technical specification with workflow contracts and command patterns
- `plan.md` - Architecture delta and file impact matrix
- `tasks.md` - Implementation tasks for workflow fixes
- `checklists/requirements.md` - Technical quality checklist

## Main Components
1. **Plan Processing**: Terraform plan binary file generation and JSON conversion
2. **Phase Detection**: jq processing to extract resource modes from plan JSON
3. **Workflow Integration**: GitHub Actions step configuration with proper output handling
4. **Artifact Management**: Binary plan file upload with 7-day retention
5. **Apply Execution**: Valid binary plan file for terraform apply

## Dependencies
- Requires Terraform >=1.5.0
- Depends on GitHub Actions Ubuntu runner with jq
- Builds on 000-cicd-workflows workflow infrastructure

## Quick Reference
- **Status**: Draft
- **Acceptance Criteria**: 6 machine-verifiable criteria
- **Key Fix**: Proper terraform show -json conversion and jq processing
- **Target File**: `.github/workflows/terraform-apply.yml`
- **Validation**: GitHub Actions workflow execution and CLI command testing