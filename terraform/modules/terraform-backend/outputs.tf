output "state_bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "S3 bucket ARN for state storage"
}

output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "S3 bucket name for state storage"
}

output "kms_key_arn" {
  value       = aws_kms_key.terraform_state.arn
  description = "KMS key ARN for state bucket encryption"
}

output "logs_bucket_arn" {
  value       = aws_s3_bucket.terraform_state_logs.arn
  description = "S3 logs bucket ARN for access logging"
}