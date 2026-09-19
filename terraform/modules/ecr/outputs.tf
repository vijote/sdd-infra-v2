output "repository_arns" {
  value       = { for name, r in aws_ecr_repository.this : name => r.arn }
  description = "ECR repository ARNs keyed by repository name"
}

output "repository_urls" {
  value       = { for name, r in aws_ecr_repository.this : name => r.repository_url }
  description = "ECR repository URLs (registry host + path) for image references"
}
