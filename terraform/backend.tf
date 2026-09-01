terraform {
  backend "s3" {
    bucket     = "sdd-k8s-platform-terraform-state"
    key        = "main/terraform.tfstate"
    region     = "us-east-1"
    encrypt    = true
    lock_table = null # Using S3 native locking instead

    # S3 native locking configuration
    skip_s3_checksum = false

    # State versioning and locking
    dynamodb_table = null # Not using DynamoDB for locking

    # Enhanced security
    access_logging = true

    # Workspace management
    workspace_key_prefix = "workspaces"
  }

  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
}