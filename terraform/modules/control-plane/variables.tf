variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID from 002-vpc-foundation"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs from 002-vpc-foundation (control plane uses index 0)"
}

variable "control_plane_security_group_id" {
  type        = string
  description = "Control plane security group ID from 003-1-cluster-plumbing"
}

variable "node_iam_instance_profile_name" {
  type        = string
  description = "IAM instance profile name from 003-1-cluster-plumbing"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default     = {}
}
