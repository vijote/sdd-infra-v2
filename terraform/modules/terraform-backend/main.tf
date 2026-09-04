# S3 Bucket for Terraform State (existing)
data "aws_s3_bucket" "existing" {
  bucket = var.state_bucket_name
}

# Enable S3 bucket versioning
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = data.aws_s3_bucket.existing.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable S3 bucket server-side encryption with KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = data.aws_s3_bucket.existing.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = data.aws_s3_bucket.existing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# KMS Key for S3 bucket encryption
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "Terraform State KMS Key"
    Project     = "sdd-k8s-platform"
    Phase       = "2"
    Environment = "dev"
  }
}

# KMS Key alias
resource "aws_kms_alias" "terraform_state" {
  name          = "alias/terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# S3 bucket policy for HTTPS enforcement
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = data.aws_s3_bucket.existing.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          data.aws_s3_bucket.existing.arn,
          "${data.aws_s3_bucket.existing.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# S3 bucket for access logging
resource "aws_s3_bucket" "terraform_state_logs" {
  bucket = "${var.state_bucket_name}-logs"

  tags = {
    Name        = "Terraform State Logs Bucket"
    Project     = "sdd-k8s-platform"
    Phase       = "2"
    Environment = "dev"
  }
}

# Block public access to logs bucket
resource "aws_s3_bucket_public_access_block" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable S3 access logging
resource "aws_s3_bucket_logging" "terraform_state" {
  bucket = data.aws_s3_bucket.existing.id

  target_bucket = aws_s3_bucket.terraform_state_logs.id
  target_prefix = "log/"

  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}