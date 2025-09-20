output "customer_documents_bucket_name" {
  description = "Name of the customer documents S3 bucket"
  value       = aws_s3_bucket.customer_documents.bucket
}

output "customer_documents_bucket_arn" {
  description = "ARN of the customer documents S3 bucket"
  value       = aws_s3_bucket.customer_documents.arn
}

output "customer_documents_bucket_domain_name" {
  description = "Domain name of the customer documents S3 bucket"
  value       = aws_s3_bucket.customer_documents.bucket_domain_name
}

output "litellm_data_bucket_name" {
  description = "Name of the LiteLLM data S3 bucket"
  value       = aws_s3_bucket.litellm_data.bucket
}

output "litellm_data_bucket_arn" {
  description = "ARN of the LiteLLM data S3 bucket"
  value       = aws_s3_bucket.litellm_data.arn
}

output "litellm_data_bucket_domain_name" {
  description = "Domain name of the LiteLLM data S3 bucket"
  value       = aws_s3_bucket.litellm_data.bucket_domain_name
}

output "s3_access_policy_arn" {
  description = "ARN of the S3 access policy"
  value       = aws_iam_policy.s3_access.arn
}

output "bucket_suffix" {
  description = "Random suffix used for bucket names"
  value       = random_id.bucket_suffix.hex
}