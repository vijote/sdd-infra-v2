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

output "control_plane_security_group_id" {
  value       = module.cluster_plumbing.control_plane_security_group_id
  description = "Control plane security group ID for EKS cluster"
}

output "worker_security_group_id" {
  value       = module.cluster_plumbing.worker_security_group_id
  description = "Worker node security group ID for EKS node group"
}

output "node_iam_instance_profile_name" {
  value       = module.cluster_plumbing.node_iam_instance_profile_name
  description = "IAM instance profile name for EKS worker nodes"
}
