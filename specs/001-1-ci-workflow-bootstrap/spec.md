# Spec: CI Workflow Bootstrap

**Feature Branch**: `001-1-ci-workflow-bootstrap` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: GitHub Actions Workflows / AWS IAM Role Chaining / CI/CD Pipeline
- **Kubernetes / Cluster Scope**: None (CI/CD infrastructure only)
- **Target Services / Modules**: Terraform Apply Workflow, AWS Credentials Configuration
- **Security & CI/CD**: GitHub OIDC, AWS Role Chaining, Environment Variables

### 1.1 GitHub Actions Workflow Contracts
```yaml
# Workflow Environment Variables
env:
  AWS_REGION: ${{ vars.AWS_REGION }}
  AWS_BOOTSTRAP_ROLE_ARN: ${{ vars.AWS_BOOTSTRAP_ROLE_ARN }}
  AWS_TERRAFORM_ROLE: ${{ vars.AWS_TERRAFORM_ROLE }}
  TF_VAR_state_bucket_name: ${{ vars.TF_VAR_state_bucket_name }}

# AWS Credentials Configuration
- name: Configure AWS Bootstrap Credentials
  uses: aws-actions/configure-aws-credentials@v6
  with:
    role-to-assume: ${{ env.AWS_BOOTSTRAP_ROLE_ARN }}
    aws-region: ${{ env.AWS_REGION }}

- name: Assume Terraform Target Role
  uses: aws-actions/configure-aws-credentials@v6
  with:
    role-to-assume: ${{ env.AWS_TERRAFORM_ROLE }}
    aws-region: ${{ env.AWS_REGION }}
    role-chaining: true

# Terraform Apply Configuration
- name: Terraform Apply
  run: |
    cd terraform/environments/dev
    terraform init
    terraform apply -auto-approve
  env:
    TF_VAR_state_bucket_name: ${{ env.TF_VAR_state_bucket_name }}
    TF_VAR_region: ${{ env.AWS_REGION }}
```

### 1.2 GitHub Variables Schema
```yaml
# Required Variables
AWS_REGION: string                    # AWS region (e.g., "us-east-1")
AWS_BOOTSTRAP_ROLE_ARN: string        # GitHub OIDC bootstrap role ARN
AWS_TERRAFORM_ROLE: string            # Terraform execution role ARN
TF_VAR_state_bucket_name: string      # S3 state bucket name (pre-existing)

# Optional Variables
AWS_ASSUME_ROLE_ARN: string           # Additional assume role for chaining
```

### 1.3 Workflow Trigger Contracts
```yaml
on:
  push:
    branches: [main]
    paths: ['terraform/**']
  workflow_dispatch:
```

### 1.4 Directory Structure Contracts
```
terraform/
├── modules/
│   └── terraform-backend/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
└── environments/
    └── dev/
        ├── main.tf
        ├── variables.tf
        ├── backend.tf
        └── terraform.tfvars
```

## 2. Assumptions & Technical Constraints
- **State Bucket**: S3 state bucket must be pre-created manually before workflow execution
- **IAM Roles**: GitHub OIDC bootstrap role and Terraform execution role must exist in AWS
- **Role Chaining**: Bootstrap role must have permission to assume Terraform role
- **Directory Structure**: Terraform code must follow the specified directory layout
- **Constitution Compliance**: No validation, testing, or verification steps in workflow
- **Provider Versions**: Terraform >= 1.5.0, AWS provider >= 5.0.0