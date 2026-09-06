output "worker_instance_ids" {
  value       = sort([for _, inst in aws_instance.worker : inst.id])
  description = "Worker EC2 instance IDs (consumed by 003-3 verification AC-003)"
}
