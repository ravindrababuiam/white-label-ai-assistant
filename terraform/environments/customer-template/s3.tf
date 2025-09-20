# S3 bucket for customer document storage
resource "aws_s3_bucket" "customer_documents" {
  bucket = "${var.customer_name}-documents-${random_id.bucket_suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "${var.customer_name}-documents-bucket"
  })
}

resource "aws_s3_bucket_versioning" "customer_documents" {
  bucket = aws_s3_bucket.customer_documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "customer_documents" {
  bucket = aws_s3_bucket.customer_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
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
  bucket = aws_s3_bucket.customer_documents.id

  rule {
    id     = "document_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# S3 bucket for LiteLLM logs and data
resource "aws_s3_bucket" "litellm_data" {
  bucket = "${var.customer_name}-litellm-data-${random_id.bucket_suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "${var.customer_name}-litellm-data-bucket"
  })
}

resource "aws_s3_bucket_versioning" "litellm_data" {
  bucket = aws_s3_bucket.litellm_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "litellm_data" {
  bucket = aws_s3_bucket.litellm_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
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

# Random suffix for bucket names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}