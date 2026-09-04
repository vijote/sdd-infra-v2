# Spec: Existing Bucket Data Source

**Feature Branch**: `001-6-existing-bucket-data-source` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform Data Source Configuration / S3 Bucket Reference
- **Kubernetes / Cluster Scope**: None (Terraform configuration only)
- **Target Services / Modules**: terraform-backend module
- **Security & CI/CD**: None (configuration change only)

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Current Bucket Resource (to be removed)
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name
}

# Target Bucket Data Source (after modification)
data "aws_s3_bucket" "existing" {
  bucket = var.state_bucket_name
}

# Updated Resource References (after modification)
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = data.aws_s3_bucket.existing.id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = data.aws_s3_bucket.existing.id
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = data.aws_s3_bucket.existing.id
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = data.aws_s3_bucket.existing.id
}

resource "aws_s3_bucket_logging" "terraform_state" {
  bucket = data.aws_s3_bucket.existing.id
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
None - This is a Terraform-only configuration change.

### 1.3 Data & Storage Contracts
None - No data or storage changes involved.

### 1.4 Network & Security Contracts
None - No network or security changes involved.

## 2. Technical Acceptance Criteria

- [ ] AC-001: aws_s3_bucket resource removed from terraform module
- [ ] AC-002: aws_s3_bucket data source added to terraform module
- [ ] AC-003: All bucket configuration resources reference data source instead of resource
- [ ] AC-004: Module outputs reference data source attributes

## 3. Assumptions & Technical Constraints

- **Existing Bucket**: S3 bucket already manually created and configured
- **Data Source Benefits**: Validation, type safety, DRY principle, error prevention
- **No Lifecycle Management**: Terraform will not manage bucket lifecycle
- **Configuration Management**: Other resources (KMS, policies, logging) still managed by Terraform
- **Testing Policy**: No validation or testing steps - user will verify via terraform apply in CI
- **Impact**: Configuration change with no infrastructure modifications