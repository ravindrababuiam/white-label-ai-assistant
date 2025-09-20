# Outputs for Customer S3 Module

output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.documents.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.documents.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.documents.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.documents.bucket_regional_domain_name
}

output "kms_key_id" {
  description = "ID of the KMS key used for bucket encryption"
  value       = aws_kms_key.s3_key.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for bucket encryption"
  value       = aws_kms_key.s3_key.arn
}

output "kms_alias_name" {
  description = "Alias name of the KMS key"
  value       = aws_kms_alias.s3_key_alias.name
}

output "vpc_endpoint_id" {
  description = "ID of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_dns_names" {
  description = "DNS names of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.s3.dns_entry[*].dns_name
}

output "bucket_policy_json" {
  description = "JSON representation of the bucket policy"
  value       = aws_s3_bucket_policy.documents.policy
}