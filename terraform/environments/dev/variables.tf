variable "state_bucket_name" {
  type        = string
  description = "S3 bucket name for Terraform state"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "ingress_host" {
  type        = string
  description = "Ingress host (Route53 domain)"
  default     = "demo.vijote.dev"
}

variable "backend_image_tag" {
  type        = string
  description = "Backend image tag (git SHA). Empty = keep public baseline image."
  default     = ""
}

variable "frontend_image_tag" {
  type        = string
  description = "Frontend image tag (git SHA). Empty = keep public baseline image."
  default     = ""
}