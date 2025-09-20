# S3 Module for Customer Document Storage and LiteLLM Data

# Random suffix for bucket names to ensure uniqueness
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 bucket for customer document storage
resource "aws_s3_bucket" "customer_documents" {
  bucket = "${var.customer_name}-documents-${random_id.bucket_suffix.hex}"

  tags = merge(var.tags, {
    Name = "${var.customer_name}-documents-bucket"
  })
}

resource "aws_s3_bucket_versioning" "customer_documents" {
  bucket = aws_s3_bucket.customer_documents.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "customer_documents" {
  bucket = aws_s3_bucket.customer_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.encryption_algorithm
    }
  }
}

resource "aws_s3_bucket_public_access_block" "customer_documents" {
  bucket = aws_s3_bucket.customer_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "customer_documents" {
  count  = var.enable_lifecycle ? 1 : 0
  bucket = aws_s3_bucket.customer_documents.id

  rule {
    id     = "document_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.transition_to_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}

# S3 bucket for LiteLLM logs and data
resource "aws_s3_bucket" "litellm_data" {
  bucket = "${var.customer_name}-litellm-data-${random_id.bucket_suffix.hex}"

  tags = merge(var.tags, {
    Name = "${var.customer_name}-litellm-data-bucket"
  })
}

resource "aws_s3_bucket_versioning" "litellm_data" {
  bucket = aws_s3_bucket.litellm_data.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "litellm_data" {
  bucket = aws_s3_bucket.litellm_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.encryption_algorithm
    }
  }
}

resource "aws_s3_bucket_public_access_block" "litellm_data" {
  bucket = aws_s3_bucket.litellm_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM policy for S3 access
resource "aws_iam_policy" "s3_access" {
  name        = "${var.customer_name}-s3-access-policy"
  description = "Policy for accessing customer S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.customer_documents.arn,
          "${aws_s3_bucket.customer_documents.arn}/*",
          aws_s3_bucket.litellm_data.arn,
          "${aws_s3_bucket.litellm_data.arn}/*"
        ]
      }
    ]
  })

  tags = var.tags
}