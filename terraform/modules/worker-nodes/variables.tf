variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID from 002-vpc-foundation"

  validation {
    condition     = can(regex("^vpc-[a-z0-9]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0a1b2c3d4e5f6g7h8)."
  }
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs from 002-vpc-foundation (control plane uses index 0; workers use indices 1 and 2)"

  validation {
    condition     = length(var.private_subnet_ids) >= 3
    error_message = "private_subnet_ids must contain at least 3 subnets (index 0 = control plane, indices 1 and 2 = workers)."
  }
}

variable "worker_security_group_id" {
  type        = string
  description = "Worker security group ID from 003-1-cluster-plumbing"

  validation {
    condition     = can(regex("^sg-[a-z0-9]{8,17}$", var.worker_security_group_id))
    error_message = "worker_security_group_id must be a valid security group ID (e.g. sg-0a1b2c3d4e5f6g7h8)."
  }
}

variable "node_iam_instance_profile_name" {
  type        = string
  description = "IAM instance profile name from 003-1-cluster-plumbing"

  validation {
    condition     = length(var.node_iam_instance_profile_name) > 0
    error_message = "node_iam_instance_profile_name must not be empty."
  }
}

variable "control_plane_instance_id" {
  type        = string
  description = "Control plane EC2 instance ID from 003-2-control-plane (declared per module interface; consumed by the Flannel CNI null_resource in the dev environment)"

  validation {
    condition     = can(regex("^i-[a-z0-9]{8,17}$", var.control_plane_instance_id))
    error_message = "control_plane_instance_id must be a valid EC2 instance ID (e.g. i-0a1b2c3d4e5f6g7h8)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default     = {}
}
