# Spec: Remove Tags Property from Terraform Module

**Feature Branch**: `001-4-remove-tags-property` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform Module Configuration / Environment Variables
- **Kubernetes / Cluster Scope**: None (Terraform configuration only)
- **Target Services / Modules**: terraform-backend module in dev environment
- **Security & CI/CD**: None (configuration cleanup only)

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Current Module Configuration (to be modified)
module "terraform_backend" {
  source = "../../modules/terraform-backend"
  
  state_bucket_name = var.state_bucket_name
  region            = var.region
  tags = {           # ← This property needs to be removed
    Project = "sdd-k8s-platform"
    Phase   = "2"
  }
}

# Target Module Configuration (after modification)
module "terraform_backend" {
  source = "../../modules/terraform-backend"
  
  state_bucket_name = var.state_bucket_name
  region            = var.region
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
None - This is a Terraform-only configuration change.

### 1.3 Data & Storage Contracts
None - No data or storage changes involved.

### 1.4 Network & Security Contracts
None - No network or security changes involved.

## 2. Technical Acceptance Criteria

- [ ] AC-001: Tags property removed from module configuration in `terraform/environments/dev/main.tf`
- [ ] AC-002: Module configuration contains only required parameters (state_bucket_name, region)
- [ ] AC-003: No syntax errors in modified Terraform configuration

## 3. Assumptions & Technical Constraints

- **Module Interface**: The terraform-backend module does not require tags parameter
- **Backward Compatibility**: Removing tags will not break existing infrastructure
- **Testing Policy**: No validation or testing steps - user will verify via terraform apply in CI
- **Impact**: This is a configuration cleanup with no infrastructure changes