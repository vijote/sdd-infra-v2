output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID for downstream phases"
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnet_ids
  description = "Private subnet IDs for cluster control plane and worker nodes"
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnet_ids
  description = "Public subnet IDs"
}
