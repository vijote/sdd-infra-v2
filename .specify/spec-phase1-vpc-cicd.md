# Spec: Phase 1 - Foundation Layer VPC with CI/CD

**Feature Branch**: `001-foundation-vpc-cicd` | **Date**: 2026-09-01 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: AWS VPC / Public & Private Subnets / Internet Gateway / NAT Gateways / Route Tables / Security Groups / EC2 Key Pair / IAM OIDC Roles
- **Kubernetes / Cluster Scope**: None (Phase 1 is infrastructure only)
- **Target Services / Modules**: GitHub Actions OIDC authentication, Terraform state backend configuration
- **Security & CI/CD**: GitHub OIDC trust relationship, AWS IAM roles for Terraform execution, no static credentials

### 1.1 Terraform / HCL Resource Contracts

```hcl
# VPC Module Input Variables
variable "vpc_cidr" {
  type        = string
  description = "Primary CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of AZs for subnet deployment"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

# VPC Module Outputs
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC identifier for resource references"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "Public subnet IDs for control plane placement"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "Private subnet IDs for worker node placement"
}

output "internet_gateway_id" {
  value       = aws_internet_gateway.main.id
  description = "IGW ID for route table associations"
}

output "nat_gateway_ids" {
  value       = aws_nat_gateway.main[*].id
  description = "NAT Gateway IDs for private subnet egress"
}

# Security Group Module Contracts
resource "aws_security_group" "control_plane" {
  name_prefix = "k8s-control-plane-"
  description = "Security group for Kubernetes control plane nodes"
  
  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "worker_nodes" {
  name_prefix = "k8s-workers-"
  description = "Security group for Kubernetes worker nodes"
  
  ingress {
    description = "Node port services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    security_groups = [aws_security_group.control_plane.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 1.2 GitHub Actions OIDC Contracts

```yaml
# .github/workflows/terraform.yml
permissions:
  id-token: write
  contents: read
  pull-requests: write

env:
  AWS_REGION: us-east-1
  TF_VERSION: 1.5.7

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_TERRAFORM_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
```

### 1.3 Data & Storage Contracts

- **Terraform State**: S3 backend with encryption enabled, DynamoDB locking table
- **State Bucket**: Pre-manual creation required to avoid circular dependencies
- **Lock Table**: DynamoDB with pay-per-request billing mode

### 1.4 Network & Security Contracts

- **VPC CIDR**: 10.0.0.0/16 (non-overlapping with on-prem)
- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24 (for control plane)
- **Private Subnets**: 10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24 (for workers)
- **NAT Gateways**: One per AZ for high availability
- **Security Groups**: Least-privilege rules, specific port ranges only

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:

- [ ] AC-001: Terraform syntax validation passes (`terraform fmt -check && terraform validate`)
- [ ] AC-002: VPC creation succeeds with correct CIDR (`aws ec2 describe-vpcs --vpc-ids [vpc-id] --query 'Vpcs[0].CidrBlock'`)
- [ ] AC-003: All subnets created and associated with correct route tables (`aws ec2 describe-subnets --filters Name=vpc-id,Values=[vpc-id]`)
- [ ] AC-004: Internet Gateway attached to VPC (`aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=[vpc-id]`)
- [ ] AC-005: NAT Gateways created in each AZ with EIP allocation (`aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=[vpc-id]`)
- [ ] AC-006: Route tables configured correctly (public routes to IGW, private to NAT) (`aws ec2 describe-route-tables --filters Name=vpc-id,Values=[vpc-id]`)
- [ ] AC-007: Security groups created with correct ingress/egress rules (`aws ec2 describe-security-groups --group-ids [sg-ids]`)
- [ ] AC-008: GitHub Actions OIDC authentication succeeds (workflow runs without static credentials)
- [ ] AC-009: Terraform state backend configured and accessible (`terraform state list` returns resources)
- [ ] AC-010: No hardcoded environment paths in backend configuration

## 3. Assumptions & Technical Constraints

- **Network CIDRs**: VPC 10.0.0.0/16, public subnets 10.0.1-3.0/24, private subnets 10.0.11-13.0/24
- **IAM / Security Boundaries**: GitHub Actions role with ec2:*, iam:*, ssm:* permissions for bootstrap
- **Storage / Backup Boundaries**: Terraform state encrypted at rest in S3, versioning enabled
- **Testing Policy**: Validation performed directly against AWS infrastructure using AWS CLI
- **Region Constraint**: us-east-1 (hardcoded for Phase 1, parameterized in later phases)
- **Provider Version**: Terraform AWS provider ~> 5.0, Terraform >= 1.5.7
- **OIDC Provider**: GitHub Actions OIDC provider must be manually created in AWS IAM console