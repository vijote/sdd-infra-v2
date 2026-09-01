# GitHub OIDC Configuration
variable "github_oidc_role_arn" {
  type        = string
  description = "GitHub Actions OIDC role ARN for AWS authentication"
}

variable "github_owner" {
  type        = string
  description = "GitHub repository owner"
  default     = ""
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
  default     = ""
}

# State Backend Configuration
variable "state_bucket_name" {
  type        = string
  description = "S3 bucket for Terraform state"
  default     = "sdd-k8s-platform-terraform-state"
}

# AWS Region
variable "region" {
  type        = string
  description = "AWS region for deployment"
  default     = "us-east-1"
}

# Database Credentials
variable "mysql_root_password" {
  type        = string
  description = "MySQL root password"
  sensitive   = true
}

variable "mysql_password" {
  type        = string
  description = "MySQL application password"
  sensitive   = true
}

# Infrastructure Configuration
variable "cluster_name" {
  type        = string
  description = "Kubernetes cluster name"
  default     = "sdd-k8s-platform"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDR blocks"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDR blocks"
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}