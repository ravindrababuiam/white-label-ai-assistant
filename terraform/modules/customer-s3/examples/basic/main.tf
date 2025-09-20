# Example: Basic S3 bucket deployment for a customer

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Example VPC (in real deployment, this would be provided)
resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "example-customer-vpc"
  }
}

resource "aws_subnet" "private" {
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
  state = "available"
}

# Customer S3 bucket module usage
module "customer_s3" {
  source = "../../"

  customer_name      = "example-customer"
  environment        = "prod"
  vpc_id            = aws_vpc.example.id
  private_subnet_ids = aws_subnet.private[*].id

  # Lifecycle configuration
  lifecycle_transition_ia_days          = 30
  lifecycle_transition_glacier_days     = 90
  lifecycle_transition_deep_archive_days = 365

  # Security configuration
  kms_deletion_window = 7
  allowed_service_principals = [
    "ec2.amazonaws.com",
    "ecs-tasks.amazonaws.com",
    "eks.amazonaws.com"
  ]

  common_tags = {
    Project     = "White Label AI Assistant"
    Environment = "production"
    Owner       = "platform-team"
    Customer    = "example-customer"
    CostCenter  = "engineering"
  }
}

# Outputs
output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = module.customer_s3.bucket_name
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = module.customer_s3.bucket_arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = module.customer_s3.kms_key_arn
}

output "vpc_endpoint_id" {
  description = "ID of the S3 VPC endpoint"
  value       = module.customer_s3.vpc_endpoint_id
}