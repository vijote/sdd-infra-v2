output "worker_instance_ids" {
  value       = sort([for id in aws_instance.worker[*].id : id])
  description = "Worker EC2 instance IDs (consumed by 003-3 verification AC-003)"
}
