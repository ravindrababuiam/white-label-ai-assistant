# Customer S3 Bucket Module
# Provisions secure S3 buckets for customer document storage with encryption and lifecycle policies

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# KMS Key for S3 bucket encryption
resource "aws_kms_key" "s3_key" {
  description             = "KMS key for ${var.customer_name} S3 bucket encryption"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  tags = merge(var.common_tags, {
    Name        = "${var.customer_name}-s3-kms-key"
    Purpose     = "S3 Encryption"
    Customer    = var.customer_name
  })
}

resource "aws_kms_alias" "s3_key_alias" {
  name          = "alias/${var.customer_name}-s3-encryption"
  target_key_id = aws_kms_key.s3_key.key_id
}

# S3 Bucket for document storage
resource "aws_s3_bucket" "documents" {
  bucket = "${var.customer_name}-${var.environment}-documents-${random_id.bucket_suffix.hex}"

  tags = merge(var.common_tags, {
    Name        = "${var.customer_name}-documents-bucket"
    Purpose     = "Document Storage"
    Customer    = var.customer_name
    Environment = var.environment
  })
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "document_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Transition to IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Transition to Deep Archive after 365 days
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    # Delete non-current versions after 90 days
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Optional rule for temporary files cleanup
  rule {
    id     = "temp_files_cleanup"
    status = "Enabled"

    filter {
      prefix = "temp/"
    }

    expiration {
      days = 7
    }
  }
}

# VPC Endpoint for S3 (secure access from customer VPC)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  
  tags = merge(var.common_tags, {
    Name        = "${var.customer_name}-s3-vpc-endpoint"
    Purpose     = "Secure S3 Access"
    Customer    = var.customer_name
  })
}

# Route table association for VPC endpoint
resource "aws_vpc_endpoint_route_table_association" "s3" {
  count           = length(data.aws_route_tables.private.ids)
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  route_table_id  = data.aws_route_tables.private.ids[count.index]
}

# Data sources
data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_route_tables" "private" {
  vpc_id = var.vpc_id
  
  filter {
    name   = "association.subnet-id"
    values = var.private_subnet_ids
  }
}

# IAM role for cross-region replication (if enabled)
resource "aws_iam_role" "replication" {
  count = var.enable_cross_region_replication ? 1 : 0
  name  = "${var.customer_name}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name     = "${var.customer_name}-s3-replication-role"
    Purpose  = "S3 Cross-Region Replication"
    Customer = var.customer_name
  })
}

resource "aws_iam_role_policy" "replication" {
  count = var.enable_cross_region_replication ? 1 : 0
  name  = "${var.customer_name}-s3-replication-policy"
  role  = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.documents.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.documents.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${var.replication_destination_bucket}/*"
      }
    ]
  })
}

# S3 Bucket replication configuration (if enabled)
resource "aws_s3_bucket_replication_configuration" "documents" {
  count  = var.enable_cross_region_replication ? 1 : 0
  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "replicate_all"
    status = "Enabled"

    destination {
      bucket        = var.replication_destination_bucket
      storage_class = "STANDARD_IA"
      
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.s3_key.arn
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.documents]
}

# S3 Bucket policy for secure VPC access
resource "aws_s3_bucket_policy" "documents" {
  bucket = aws_s3_bucket.documents.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyInsecureConnections"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowVPCEndpointAccess"
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceVpce" = aws_vpc_endpoint.s3.id
          }
        }
      },
      {
        Sid    = "AllowServicePrincipals"
        Effect = "Allow"
        Principal = {
          Service = var.allowed_service_principals
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# S3 Bucket notification configuration (for future integration with processing services)
resource "aws_s3_bucket_notification" "documents" {
  bucket = aws_s3_bucket.documents.id

  # Placeholder for future SQS/SNS integration
  # This can be extended when implementing document processing workflows
}