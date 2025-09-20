# Example: S3 bucket with cross-region replication for disaster recovery

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Primary region provider
provider "aws" {
  alias  = "primary"
  region = "us-east-1"
}

# Backup region provider
provider "aws" {
  alias  = "backup"
  region = "us-west-2"
}

# Backup bucket in secondary region
resource "aws_s3_bucket" "backup" {
  provider = aws.backup
  bucket   = "example-customer-backup-${random_id.backup_suffix.hex}"

  tags = {
    Name        = "example-customer-backup-bucket"
    Purpose     = "Disaster Recovery"
    Customer    = "example-customer"
    Environment = "prod"
  }
}

resource "random_id" "backup_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "backup" {
  provider = aws.backup
  bucket   = aws_s3_bucket.backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Example VPC (in real deployment, this would be provided)
resource "aws_vpc" "example" {
  provider           = aws.primary
  cidr_block         = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "example-customer-vpc"
  }
}

resource "aws_subnet" "private" {
  provider          = aws.primary
  count             = 2
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "example-private-subnet-${count.index + 1}"
    Type = "Private"
  }
}

data "aws_availability_zones" "available" {
  provider = aws.primary
  state    = "available"
}

# Customer S3 bucket module with replication
module "customer_s3" {
  source = "../../"
  providers = {
    aws = aws.primary
  }

  customer_name      = "example-customer"
  environment        = "prod"
  vpc_id            = aws_vpc.example.id
  private_subnet_ids = aws_subnet.private[*].id

  # Enable cross-region replication
  enable_cross_region_replication   = true
  replication_destination_bucket    = aws_s3_bucket.backup.arn
  replication_destination_region    = "us-west-2"

  # Lifecycle configuration
  lifecycle_transition_ia_days          = 30
  lifecycle_transition_glacier_days     = 90
  lifecycle_transition_deep_archive_days = 365

  common_tags = {
    Project     = "White Label AI Assistant"
    Environment = "production"
    Owner       = "platform-team"
    Customer    = "example-customer"
    CostCenter  = "engineering"
  }
}

# Outputs
output "primary_bucket_name" {
  description = "Name of the primary S3 bucket"
  value       = module.customer_s3.bucket_name
}

output "backup_bucket_name" {
  description = "Name of the backup S3 bucket"
  value       = aws_s3_bucket.backup.id
}

output "replication_enabled" {
  description = "Whether cross-region replication is enabled"
  value       = true
}