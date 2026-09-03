variable "state_bucket_name" {
  type        = string
  description = "S3 bucket name for Terraform state"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}