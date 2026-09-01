# Spec: S3 State Management Backend

**Feature Branch**: `002-state-backend` | **Date**: 2026-09-01 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: S3 Bucket / DynamoDB Table / IAM Policies / KMS Encryption
- **Kubernetes / Cluster Scope**: None (Infrastructure state management only)
- **Target Services / Modules**: Terraform backend configuration, state locking mechanism
- **Security & CI/CD**: Server-side encryption, access logging, state file versioning

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Input Variables / Schema
variable "state_bucket_name" {
  type        = string
  description = "S3 bucket name for Terraform state"
}

variable "state_lock_table_name" {
  type        = string
  description = "DynamoDB table name for state locking"
  default     = "terraform-locks"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

# Resource / Module Interface
module "terraform_backend" {
  source = "./src/modules/terraform-backend"
  
  state_bucket_name    = var.state_bucket_name
  state_lock_table_name = var.state_lock_table_name
  region              = var.region
  
  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "2"
  }
}

# Terraform Backend Configuration
terraform {
  backend "s3" {
    bucket         = var.state_bucket_name
    key            = "terraform.tfstate"
    region         = var.region
    encrypt        = true
    dynamodb_table = var.state_lock_table_name
  }
}

# Outputs
output "state_bucket_arn" {
  value       = module.terraform_backend.state_bucket_arn
  description = "S3 bucket ARN for state storage"
}

output "lock_table_arn" {
  value       = module.terraform_backend.lock_table_arn
  description = "DynamoDB table ARN for state locking"
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
None for Phase 2

### 1.3 Data & Storage Contracts
- **S3 Bucket**: Versioning enabled, server-side encryption with KMS, access logging
- **DynamoDB Table**: Pay-per-request billing, encryption at rest, TTL disabled
- **KMS Key**: AWS managed KMS key for S3 bucket encryption

### 1.4 Network & Security Contracts
- **S3 Bucket Policy**: Deny non-HTTPS access, restrict to specific IAM roles
- **DynamoDB IAM**: Fine-grained permissions for state lock operations
- **Encryption**: All state data encrypted at rest and in transit

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD:
- [ ] AC-001: S3 bucket created with versioning (`aws s3api get-bucket-versioning --bucket $(terraform output -raw state_bucket_name) --query 'Status' --output text | grep -q 'Enabled'`)
- [ ] AC-002: S3 bucket encryption enabled (`aws s3api get-bucket-encryption --bucket $(terraform output -raw state_bucket_name) --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text | grep -q 'AES256'`)
- [ ] AC-003: DynamoDB table created with encryption (`aws dynamodb describe-table --table-name $(terraform output -raw state_lock_table_name) --query 'Table.SSEDescription.Status' --output text | grep -q 'ENABLED'`)
- [ ] AC-004: Terraform can initialize backend (`terraform init && terraform validate`)
- [ ] AC-005: Terraform state can be locked (`terraform apply -auto-approve -target=module.terraform_backend && terraform force-unlock LOCK_ID 2>/dev/null || true`)
- [ ] AC-006: S3 access logging configured (`aws s3api get-bucket-logging --bucket $(terraform output -raw state_bucket_name) --query 'LoggingEnabled.TargetBucket' --output text`)
- [ ] AC-007: Bucket policy enforces HTTPS (`aws s3api get-bucket-policy --bucket $(terraform output -raw state_bucket_name) --query 'Policy' --output text | grep -q '"ssl": "true"'`)
- [ ] AC-008: State file persists after apply/destroy cycles (`aws s3 ls s3://$(terraform output -raw state_bucket_name)/terraform.tfstate && test -n "$(aws s3 ls s3://$(terraform output -raw state_bucket_name)/terraform.tfstate)"`)

## 3. Assumptions & Technical Constraints
- **State Bucket Naming**: Must be globally unique S3 bucket name
- **IAM Boundaries**: GitHub Actions role requires S3 and DynamoDB permissions
- **Storage / Backup Boundaries**: S3 versioning provides state history, no additional backup needed
- **Testing Policy**: No unit or E2E test generation - validation performed directly against AWS infrastructure using CLI tools
- **Provider Versions**: Terraform >= 1.5.0, AWS provider >= 5.0.0