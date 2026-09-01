# SDD Kubernetes Platform - Main Configuration
# This file orchestrates all infrastructure phases in a single apply

provider "aws" {
  region = var.region
}

# Phase 001: VPC Foundation
module "vpc_foundation" {
  source = "../specs/001-vpc-foundation/terraform"

  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr

  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = {
    Project   = "sdd-k8s-platform"
    Phase     = "001-vpc-foundation"
    ManagedBy = "terraform"
  }
}

# Phase 002: State Backend
module "state_backend" {
  source = "../specs/002-state-backend/terraform"

  state_bucket_name = var.state_bucket_name
  region            = var.region

  depends_on = [module.vpc_foundation]

  tags = {
    Project   = "sdd-k8s-platform"
    Phase     = "002-state-backend"
    ManagedBy = "terraform"
  }
}

# Phase 003: Compute Cluster
module "compute_cluster" {
  source = "../specs/003-compute-cluster/terraform"

  cluster_name = var.cluster_name
  region       = var.region

  vpc_id             = module.vpc_foundation.vpc_id
  public_subnet_ids  = module.vpc_foundation.public_subnet_ids
  private_subnet_ids = module.vpc_foundation.private_subnet_ids

  depends_on = [module.state_backend]

  tags = {
    Project   = "sdd-k8s-platform"
    Phase     = "003-compute-cluster"
    ManagedBy = "terraform"
  }
}

# Phase 004: Application Infrastructure
module "app_infrastructure" {
  source = "../specs/004-app-infrastructure/terraform"

  cluster_name = var.cluster_name

  vpc_id             = module.vpc_foundation.vpc_id
  private_subnet_ids = module.vpc_foundation.private_subnet_ids

  depends_on = [module.compute_cluster]

  tags = {
    Project   = "sdd-k8s-platform"
    Phase     = "004-app-infrastructure"
    ManagedBy = "terraform"
  }
}

# Phase 005: Application Deployment
module "app_deployment" {
  source = "../specs/005-app-deployment/terraform"

  cluster_name = var.cluster_name

  mysql_root_password = var.mysql_root_password
  mysql_password      = var.mysql_password

  depends_on = [module.app_infrastructure]

  tags = {
    Project   = "sdd-k8s-platform"
    Phase     = "005-app-deployment"
    ManagedBy = "terraform"
  }
}

# Outputs for consumption by workflows and other phases
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc_foundation.vpc_id
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.compute_cluster.cluster_endpoint
}

output "application_url" {
  description = "Application load balancer URL"
  value       = module.app_deployment.application_url
}

output "state_bucket_arn" {
  description = "S3 state bucket ARN"
  value       = module.state_backend.state_bucket_arn
}