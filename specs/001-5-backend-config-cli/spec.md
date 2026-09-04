# Spec: Backend Config CLI

**Feature Branch**: `001-5-backend-config-cli` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform Backend Configuration / GitHub Actions Workflow
- **Kubernetes / Cluster Scope**: None (Terraform configuration only)
- **Target Services / Modules**: terraform-backend module, GitHub Actions workflow
- **Security & CI/CD**: GitHub repository variables, AWS IAM role chaining

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Current Backend Configuration (to be modified)
terraform {
  backend "s3" {
    bucket  = var.state_bucket_name  # ← Variables not allowed in backend block
    key     = "terraform.tfstate"
    region  = var.region             # ← Variables not allowed in backend block
    encrypt = true
  }
}

# Target Backend Configuration (after modification)
terraform {
  backend "s3" {
    key     = "terraform.tfstate"
    encrypt = true
    # bucket and region provided via -backend-config CLI arguments
  }
}
```

### 1.2 GitHub Actions Workflow Contracts
```yaml
# Current Terraform Init (to be modified)
- name: Terraform Apply
  run: |
    cd terraform/environments/dev
    terraform init
    terraform apply -auto-approve

# Target Terraform Init (after modification)
- name: Terraform Apply
  run: |
    cd terraform/environments/dev
    terraform init \
      -backend-config="bucket=${{ env.TF_VAR_state_bucket_name }}" \
      -backend-config="region=${{ env.AWS_REGION }}"
    terraform apply -auto-approve
```

### 1.3 Data & Storage Contracts
None - No data or storage changes involved.

### 1.4 Network & Security Contracts
None - No network or security changes involved.

## 2. Technical Acceptance Criteria

- [ ] AC-001: Backend configuration in `terraform/environments/dev/backend.tf` removes variable references
- [ ] AC-002: GitHub Actions workflow updates terraform init with -backend-config arguments
- [ ] AC-003: Backend configuration uses environment variables for dynamic values
- [ ] AC-004: No hardcoded values in backend configuration

## 3. Assumptions & Technical Constraints

- **Terraform Limitation**: Variables cannot be used in terraform backend block
- **CLI Approach**: -backend-config is the standard Terraform solution for dynamic backend configuration
- **Environment Variables**: GitHub repository variables provide bucket name and region
- **Local Development**: Same CLI approach works for local terraform init
- **Testing Policy**: No validation or testing steps - user will verify via terraform apply in CI
- **Impact**: Resolves Terraform variable limitation while maintaining dynamic configuration