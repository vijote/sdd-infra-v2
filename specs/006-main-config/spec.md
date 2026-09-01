# Spec: Main Configuration

**Feature Branch**: `006-main-config` | **Date**: 2026-09-01 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Module Composition / Remote State / Data Sources / Provider Configuration
- **Kubernetes / Cluster Scope**: kubeconfig generation / Cluster access configuration
- **Target Services / Modules**: Root module orchestrating all phases
- **Security & CI/CD**: State management, provider authentication, data passing between modules

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Input Variables / Schema
variable "region" {
  type        = string
  description = "AWS region for deployment"
  default     = "us-east-1"
}

variable "github_owner" {
  type        = string
  description = "GitHub repository owner"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
}

variable "mysql_root_password" {
  type        = string
  description = "Base64 encoded MySQL root password"
  sensitive   = true
}

variable "mysql_password" {
  type        = string
  description = "Base64 encoded MySQL application password"
  sensitive   = true
}

# Provider Configuration
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10.0"
    }
  }
  
  backend "s3" {
    bucket = "sdd-k8s-platform-terraform-state"
    key    = "main/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.region
}

# Module Composition
module "phase1_vpc" {
  source = "./specs/001-vpc-foundation/src"
  
  region            = var.region
  github_owner      = var.github_owner
  github_repo       = var.github_repo
}

module "phase2_backend" {
  source = "./specs/002-state-backend/src"
  
  state_bucket_name    = "sdd-k8s-platform-terraform-state"
  state_lock_table_name = "terraform-locks"
  region              = var.region
  
  depends_on = [module.phase1_vpc]
}

module "phase3_cluster" {
  source = "./specs/003-compute-cluster/src"
  
  kubernetes_version              = "v1.28.0"
  control_plane_instance_type    = "t2.medium"
  worker_instance_type           = "t2.small"
  vpc_id                         = module.phase1_vpc.vpc_id
  private_subnet_ids             = module.phase1_vpc.private_subnet_ids
  control_plane_security_group_id = module.phase1_vpc.control_plane_security_group_id
  worker_security_group_id       = module.phase1_vpc.worker_security_group_id
  
  depends_on = [module.phase2_backend]
}

module "phase4_infrastructure" {
  source = "./specs/004-app-infrastructure/src"
  
  cluster_name       = "sdd-k8s-platform"
  vpc_id            = module.phase1_vpc.vpc_id
  oidc_provider_arn = module.phase3_cluster.oidc_provider_arn
  
  depends_on = [module.phase3_cluster]
}

module "phase5_applications" {
  source = "./specs/005-app-deployment/src"
  
  mysql_root_password = var.mysql_root_password
  mysql_password      = var.mysql_password
  
  depends_on = [module.phase4_infrastructure]
}

# Kubernetes Provider Configuration
data "aws_eks_cluster" "cluster" {
  name = module.phase3_cluster.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.phase3_cluster.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Outputs
output "vpc_id" {
  value = module.phase1_vpc.vpc_id
}

output "cluster_endpoint" {
  value = module.phase3_cluster.cluster_endpoint
}

output "application_url" {
  value = module.phase5_applications.application_ingress_url
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
None for Phase 6 (orchestration only)

### 1.3 Data & Storage Contracts
- **State Management**: Centralized S3 backend with DynamoDB locking
- **Data Sources**: EKS cluster auth, VPC information, security group references

### 1.4 Network & Security Contracts
- **Module Dependencies**: Explicit depends_on for proper deployment order
- **Provider Authentication**: EKS auth token for Kubernetes/Helm providers
- **State Security**: Encrypted state with access logging

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD:
- [ ] AC-001: All modules initialized successfully (`terraform init -upgrade && terraform validate`)
- [ ] AC-002: Terraform plan shows all resources (`terraform plan -detailed-exitcode && test $? -eq 2`)
- [ ] AC-003: Module dependencies resolved (`terraform graph | grep -q 'module.phase' && terraform graph | grep -c '\[.*\]' | grep -v '^0$'`)
- [ ] AC-004: Kubernetes provider connected (`terraform plan -target=module.phase4_infrastructure 2>/dev/null | grep -q 'kubernetes'`)
- [ ] AC-005: Helm provider connected (`terraform plan -target=module.phase4_infrastructure 2>/dev/null | grep -q 'helm'`)
- [ ] AC-006: State file encrypted (`aws s3api head-object --bucket sdd-k8s-platform-terraform-state --key main/terraform.tfstate --query 'ServerSideEncryption' --output text | grep -q 'AES256'`)
- [ ] AC-007: All outputs accessible (`terraform output -json | jq -r 'keys[]' | wc -l | grep -v '^0$'`)
- [ ] AC-008: Full deployment successful (`terraform apply -auto-approve && terraform output -json > /tmp/outputs.json && test -s /tmp/outputs.json`)

## 3. Assumptions & Technical Constraints
- **Module Structure**: All phases have src/ directories with Terraform modules
- **State Backend**: S3 bucket and DynamoDB table created in Phase 2
- **Provider Versions**: Minimum versions enforced for compatibility
- **IAM / Security Boundaries**: GitHub Actions role with sufficient permissions
- **Testing Policy**: No unit or E2E test generation - validation performed directly against AWS infrastructure using CLI tools
- **Provider Versions**: Terraform >= 1.5.0, AWS provider >= 5.0.0, Kubernetes provider >= 2.20.0, Helm provider >= 2.10.0