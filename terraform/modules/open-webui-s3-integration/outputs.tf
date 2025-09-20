# Outputs for Open WebUI S3 Integration Module

output "document_processor_service_name" {
  description = "Name of the document processor service"
  value       = kubernetes_service.document_processor.metadata[0].name
}

output "document_processor_service_fqdn" {
  description = "Fully qualified domain name of the document processor service"
  value       = "${kubernetes_service.document_processor.metadata[0].name}.${var.namespace}.svc.cluster.local"
}

output "document_processor_endpoint" {
  description = "Document processor API endpoint"
  value       = "http://${kubernetes_service.document_processor.metadata[0].name}.${var.namespace}.svc.cluster.local:8000"
}

output "s3_bucket_name" {
  description = "S3 bucket name used for document storage"
  value       = var.s3_bucket_name
}

output "s3_region" {
  description = "S3 bucket region"
  value       = var.s3_region
}

output "config_map_name" {
  description = "Name of the ConfigMap containing S3 integration configuration"
  value       = kubernetes_config_map.s3_integration_config.metadata[0].name
}

output "secret_name" {
  description = "Name of the secret containing S3 integration credentials"
  value       = kubernetes_secret.s3_integration_secrets.metadata[0].name
}

output "service_account_name" {
  description = "Name of the service account for S3 operations (if IRSA enabled)"
  value       = var.enable_irsa ? kubernetes_service_account.s3_integration[0].metadata[0].name : null
}

output "iam_role_arn" {
  description = "ARN of the IAM role for S3 operations (if IRSA enabled)"
  value       = var.enable_irsa ? aws_iam_role.s3_integration[0].arn : null
}

output "deployment_name" {
  description = "Name of the document processor deployment"
  value       = kubernetes_deployment.document_processor.metadata[0].name
}

output "hpa_name" {
  description = "Name of the HorizontalPodAutoscaler (if enabled)"
  value       = var.enable_processor_hpa ? kubernetes_horizontal_pod_autoscaler_v2.document_processor[0].metadata[0].name : null
}

output "virus_scanning_enabled" {
  description = "Whether virus scanning is enabled"
  value       = var.enable_virus_scanning
}

output "metadata_indexing_enabled" {
  description = "Whether metadata indexing is enabled"
  value       = var.enable_metadata_indexing
}

output "max_file_size" {
  description = "Maximum allowed file size in bytes"
  value       = var.max_file_size
}

output "allowed_file_extensions" {
  description = "List of allowed file extensions"
  value       = var.allowed_file_extensions
}

output "processor_replicas" {
  description = "Number of document processor replicas"
  value       = var.processor_replicas
}

output "integration_status" {
  description = "S3 integration configuration status"
  value = {
    s3_configured           = var.s3_bucket_name != ""
    virus_scanning_enabled  = var.enable_virus_scanning
    metadata_indexing_enabled = var.enable_metadata_indexing
    irsa_enabled           = var.enable_irsa
    qdrant_integration     = var.qdrant_url != ""
    hpa_enabled           = var.enable_processor_hpa
  }
}