output "control_plane_instance_id" {
  value       = aws_instance.control_plane.id
  description = "Control plane EC2 instance ID"
}

output "control_plane_private_ip" {
  value       = aws_instance.control_plane.private_ip
  description = "Control plane private IP (API server endpoint, consumed by 003-3)"
}
