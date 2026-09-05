# Spec: VPC Foundation

**Feature Branch**: `002-vpc-foundation` | **Date**: 2026-09-01 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: AWS VPC / Public Subnets / Private Subnets / Internet Gateway / NAT Gateway / Route Tables
- **Kubernetes / Cluster Scope**: None (Phase 1 is foundation only)
- **Target Services / Modules**: Terraform module for VPC networking
- **Security & CI/CD**: None (CI/CD authentication roles are managed by CloudFormation stacks, see `000-8-cloudformation-circular-dependency-fix`)

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Input Variables / Schema
variable "region" {
  type        = string
  description = "AWS region for deployment"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# Resource / Module Interface
module "vpc" {
  source = "../../modules/vpc"
  
  region             = var.region
  vpc_cidr           = var.vpc_cidr
  availability_zones  = var.availability_zones
  
  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "1"
  }
}

# Outputs
output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID for downstream modules"
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnet_ids
  description = "Private subnet IDs for worker nodes"
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
None for Phase 1

### 1.3 Data & Storage Contracts
None for Phase 1

### 1.4 Network & Security Contracts
- **VPC Configuration**: 10.0.0.0/16 CIDR, 3 AZs
- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24
- **Private Subnets**: 10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24
- **NAT Gateway**: Single NAT GW in public subnet 10.0.1.0/24 (dev environment, cost-optimized)
- **Security Groups**: None for Phase 1 (cluster SGs deferred to `003-compute-cluster`)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD:
- [ ] AC-001: Terraform syntax & formatting validation passes (`terraform fmt -check && terraform validate`)
- [ ] AC-002: Terraform plan generates expected VPC resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: VPC created with correct CIDR (`aws ec2 describe-vpcs --vpc-ids $(terraform output -raw vpc_id) --query 'Vpcs[0].CidrBlock' --output text | grep -q '10.0.0.0/16'`)
- [ ] AC-004: All 6 subnets created (3 public, 3 private) (`aws ec2 describe-subnets --filters Name=vpc-id,Values=$(terraform output -raw vpc_id) --query 'length(Subnets)' --output text | grep -q '^6$'`)
- [ ] AC-005: Internet Gateway attached (`aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$(terraform output -raw vpc_id) --query 'length(InternetGateways)' --output text | grep -q '^1$'`)
- [ ] AC-006: NAT Gateway created (`aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$(terraform output -raw vpc_id) --query 'length(NatGateways)' --output text | grep -q '^1$'`)
- [ ] AC-007: Route tables created (1 main + 1 public + 1 private) (`aws ec2 describe-route-tables --filters Name=vpc-id,Values=$(terraform output -raw vpc_id) --query 'length(RouteTables)' --output text | grep -q '^3$'`)

## 3. Assumptions & Technical Constraints
- **Network CIDRs**: VPC: 10.0.0.0/16, Public: 10.0.1.0/24-10.0.3.0/24, Private: 10.0.11.0/24-10.0.13.0/24
- **IAM / Security Boundaries**: None for Phase 1 (CI/CD roles managed by CloudFormation, see `000-8-cloudformation-circular-dependency-fix`)
- **Storage / Backup Boundaries**: None for Phase 1
- **Testing Policy**: No unit or E2E test generation - validation performed directly against AWS infrastructure using CLI tools
- **Provider Versions**: Terraform >= 1.5.0, AWS provider >= 5.0.0