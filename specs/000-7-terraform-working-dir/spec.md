# Spec: Terraform Working Directory Fix

**Feature Branch**: `000-7-terraform-working-dir` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: GitHub Actions workflow configuration, Terraform working directory context
- **Kubernetes / Cluster Scope**: N/A (CI/CD workflow fix only)
- **Target Services / Modules**: `.github/workflows/terraform-apply.yml`, `terraform/` directory structure
- **Security & CI/CD**: GitHub Actions runner environment, Terraform execution context

### 1.1 Terraform / HCL Resource Contracts
```bash
# Terraform Working Directory Contract
cd terraform && terraform init
cd terraform && terraform plan -out=tfplan
cd terraform && terraform show -json tfplan > plan.json
cd terraform && terraform apply -auto-approve tfplan

# Alternative: Working Directory Parameter
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=tfplan
terraform -chdir=terraform show -json tfplan > plan.json
terraform -chdir=terraform apply -auto-approve tfplan
```

### 1.2 GitHub Actions Workflow Contract
```yaml
# Workflow Step Contract with Working Directory
- name: Terraform Init
  working-directory: ./terraform
  run: terraform init

- name: Terraform Plan
  id: plan
  working-directory: ./terraform
  run: |
    terraform plan -out=tfplan
    terraform show -json tfplan > plan.json
    phases=$(jq -r '.configuration.root_module.resources | map(.mode) | unique | join(",")' plan.json)
    echo "phases=$phases" >> $GITHUB_OUTPUT

- name: Terraform Apply
  working-directory: ./terraform
  run: terraform apply -auto-approve tfplan
```

### 1.3 Data & Storage Contracts
- **Working Directory**: `terraform/` - Root directory containing Terraform configuration files
- **State File**: `terraform/terraform.tfstate` - Local state file (before backend configuration)
- **Plan Files**: `terraform/tfplan` and `terraform/plan.json` - Generated in working directory
- **Module Sources**: Relative paths from `terraform/` directory to module sources

### 1.4 Network & Security Contracts
- **GitHub Actions Runner**: Ubuntu latest environment with Terraform >=1.5.0
- **Working Directory Context**: All Terraform commands must execute within `terraform/` directory
- **Path Resolution**: Module sources and relative paths resolved from `terraform/` directory
- **Artifact Storage**: Plan files uploaded from `terraform/` directory context

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Terraform init executes successfully from working directory (`cd terraform && terraform init` returns exit code 0)
- [ ] AC-002: Terraform plan generates expected resources from working directory (`cd terraform && terraform plan -out=tfplan` returns exit code 0)
- [ ] AC-003: Terraform show JSON conversion succeeds in working directory (`cd terraform && terraform show -json tfplan > plan.json` returns exit code 0)
- [ ] AC-004: Terraform apply executes successfully from working directory (`cd terraform && terraform apply -auto-approve tfplan` returns exit code 0)
- [ ] AC-005: GitHub Actions workflow steps complete with working-directory parameter (workflow log shows all Terraform steps with exit code 0)
- [ ] AC-006: Module sources resolve correctly from working directory (no "module not found" errors)
- [ ] AC-007: State file and plan files generated in correct directory (`terraform/` directory contains expected files)

## 3. Assumptions & Technical Constraints
- **Terraform Version**: >=1.5.0 (as specified in workflow setup)
- **Directory Structure**: `terraform/` directory exists at repository root with main.tf, variables.tf, backend.tf
- **Module Sources**: All module sources use relative paths from `terraform/` directory
- **Working Directory**: GitHub Actions default working directory is repository root
- **Path Resolution**: Terraform commands must resolve relative paths from execution context
- **Backward Compatibility**: Fix must not break existing artifact upload and apply job dependencies
- **Testing Policy**: Validation performed via GitHub Actions workflow execution and CLI command testing