output "control_plane_security_group_id" {
  value       = aws_security_group.control_plane.id
  description = "Control plane security group ID for EKS cluster"
}

output "worker_security_group_id" {
  value       = aws_security_group.worker.id
  description = "Worker node security group ID for EKS node group"
}

output "node_iam_instance_profile_name" {
  value       = aws_iam_instance_profile.node.name
  description = "IAM instance profile name for EKS worker nodes"
}
