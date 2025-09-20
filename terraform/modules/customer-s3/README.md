# Customer S3 Module

This Terraform module provisions secure S3 buckets for customer document storage with encryption, lifecycle policies, and VPC endpoint access.

## Features

- **Security**: Customer-managed KMS encryption, VPC endpoint access, secure transport enforcement
- **Cost Optimization**: Intelligent lifecycle policies for automatic storage class transitions
- **Compliance**: Versioning enabled, public access blocked, audit logging ready
- **Disaster Recovery**: Optional cross-region replication support
- **Network Isolation**: VPC endpoint for secure access without internet routing

## Usage

```hcl
module "customer_s3" {
  source = "./modules/customer-s3"

  customer_name      = "acme-corp"
  environment        = "prod"
  vpc_id            = "vpc-12345678"
  private_subnet_ids = ["subnet-12345678", "subnet-87654321"]

  common_tags = {
    Project     = "White Label AI Assistant"
    Environment = "production"
    Owner       = "platform-team"
  }

  # Optional: Enable cross-region replication
  enable_cross_region_replication   = true
  replication_destination_bucket    = "arn:aws:s3:::backup-bucket"
  replication_destination_region    = "us-west-2"
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | ~> 5.0 |
| random | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| customer_name | Name of the customer (used for resource naming) | `string` | n/a | yes |
| environment | Environment name (dev, staging, prod) | `string` | `"prod"` | no |
| vpc_id | VPC ID where the customer infrastructure is deployed | `string` | n/a | yes |
| private_subnet_ids | List of private subnet IDs for VPC endpoint | `list(string)` | n/a | yes |
| kms_deletion_window | Number of days to wait before deleting KMS key | `number` | `7` | no |
| common_tags | Common tags to apply to all resources | `map(string)` | `{}` | no |
| enable_cross_region_replication | Enable cross-region replication for disaster recovery | `bool` | `false` | no |
| replication_destination_bucket | Destination bucket ARN for cross-region replication | `string` | `""` | no |
| replication_destination_region | Destination region for cross-region replication | `string` | `""` | no |
| lifecycle_transition_ia_days | Number of days before transitioning to Standard-IA | `number` | `30` | no |
| lifecycle_transition_glacier_days | Number of days before transitioning to Glacier | `number` | `90` | no |
| lifecycle_transition_deep_archive_days | Number of days before transitioning to Deep Archive | `number` | `365` | no |
| allowed_service_principals | List of AWS service principals allowed to access the bucket | `list(string)` | `["ec2.amazonaws.com", "ecs-tasks.amazonaws.com", "eks.amazonaws.com"]` | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket_name | Name of the created S3 bucket |
| bucket_arn | ARN of the created S3 bucket |
| bucket_domain_name | Domain name of the S3 bucket |
| bucket_regional_domain_name | Regional domain name of the S3 bucket |
| kms_key_id | ID of the KMS key used for bucket encryption |
| kms_key_arn | ARN of the KMS key used for bucket encryption |
| kms_alias_name | Alias name of the KMS key |
| vpc_endpoint_id | ID of the S3 VPC endpoint |
| vpc_endpoint_dns_names | DNS names of the S3 VPC endpoint |
| bucket_policy_json | JSON representation of the bucket policy |

## Security Features

### Encryption
- Customer-managed KMS keys with automatic rotation
- Server-side encryption enforced for all objects
- Bucket key enabled for cost optimization

### Access Control
- VPC endpoint access only (no internet routing)
- Secure transport (HTTPS) enforced
- Service principal restrictions
- Public access completely blocked

### Lifecycle Management
- Automatic transition to cheaper storage classes
- Non-current version cleanup
- Incomplete multipart upload cleanup
- Temporary file cleanup

## Compliance

This module implements security best practices for:
- GDPR compliance (data sovereignty)
- SOC 2 Type II requirements
- AWS Well-Architected Framework
- Least privilege access principles

## Integration

The S3 bucket integrates with:
- Open WebUI for document uploads
- Qdrant for embedding storage metadata
- Future document processing pipelines
- Monitoring and alerting systems