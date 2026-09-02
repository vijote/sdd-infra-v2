# Spec: Terraform Workflow Fix

**Feature Branch**: `000-6-terraform-workflow-fix` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: GitHub Actions workflow configuration, Terraform CLI execution
- **Kubernetes / Cluster Scope**: N/A (CI/CD workflow fix only)
- **Target Services / Modules**: `.github/workflows/terraform-apply.yml`
- **Security & CI/CD**: GitHub Actions runner environment, Terraform binary plan file handling

### 1.1 Terraform / HCL Resource Contracts
```bash
# Terraform Plan Command Contract
terraform plan -out=tfplan

# Terraform Show JSON Command Contract  
terraform show -json tfplan > plan.json

# jq Processing Contract
jq -r '.configuration.root_module.resources | map(.mode) | unique | join(",")' plan.json
```

### 1.2 GitHub Actions Workflow Contract
```yaml
# Workflow Step Contract
- name: Terraform Plan
  id: plan
  run: |
    terraform plan -out=tfplan
    terraform show -json tfplan > plan.json
    phases=$(jq -r '.configuration.root_module.resources | map(.mode) | unique | join(",")' plan.json)
    echo "phases=$phases" >> $GITHUB_OUTPUT
```

### 1.3 Data & Storage Contracts
- **Binary Plan File**: `tfplan` - Terraform binary plan output for apply execution
- **JSON Plan File**: `plan.json` - Structured JSON representation for jq processing and phase detection
- **GitHub Output**: `phases` - Comma-separated resource modes for downstream job dependencies

### 1.4 Network & Security Contracts
- **GitHub Actions Runner**: Ubuntu latest environment with Terraform >=1.5.0
- **AWS Credentials**: OIDC role assumption via `aws-actions/configure-aws-credentials@v4`
- **Artifact Storage**: Binary plan file uploaded as GitHub artifact with 7-day retention

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Terraform plan command executes without syntax errors (`terraform plan -out=tfplan` returns exit code 0)
- [ ] AC-002: Terraform show JSON conversion succeeds (`terraform show -json tfplan > plan.json` returns exit code 0)
- [ ] AC-003: jq processing extracts resource modes successfully (`jq -r '.configuration.root_module.resources | map(.mode) | unique | join(",")' plan.json` returns valid output)
- [ ] AC-004: GitHub Actions workflow step completes successfully (workflow log shows "Terraform Plan" step with exit code 0)
- [ ] AC-005: Binary plan file is valid for apply execution (`terraform apply -auto-approve tfplan` executes without errors)
- [ ] AC-006: Phase detection output is properly set (`echo "phases=$phases" >> $GITHUB_OUTPUT` writes to GitHub Actions output)

## 3. Assumptions & Technical Constraints
- **Terraform Version**: >=1.5.0 (as specified in workflow setup)
- **jq Availability**: GitHub Actions Ubuntu runner includes jq by default
- **Plan File Compatibility**: Binary plan file must be generated in same Terraform version as apply execution
- **Workflow Path**: `.github/workflows/terraform-apply.yml` is the target file
- **Backward Compatibility**: Fix must not break existing artifact upload and apply job dependencies
- **Testing Policy**: Validation performed via GitHub Actions workflow execution and CLI command testing