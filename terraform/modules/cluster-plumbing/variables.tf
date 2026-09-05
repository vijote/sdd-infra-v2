variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID from 002-vpc-foundation"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block for security group ingress rules"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default     = {}
}
