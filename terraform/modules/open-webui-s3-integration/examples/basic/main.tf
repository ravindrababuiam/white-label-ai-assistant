# Example: Basic S3 integration for Open WebUI

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "aws" {
  region = "us-east-1"
}

# Basic S3 integration deployment
module "s3_integration" {
  source = "../../"

  customer_name   = "example-customer"
  namespace      = "open-webui"
  s3_bucket_name = "example-customer-documents"
  s3_region      = "us-east-1"
  
  # Security configuration
  enable_virus_scanning = true
  enable_content_type_validation = true
  enable_filename_sanitization = true
  quarantine_suspicious_files = true
  
  # Processing configuration
  enable_metadata_indexing = true
  extract_text_content = true
  generate_thumbnails = true
  extract_file_metadata = true
  enable_ocr = false  # Disabled for basic example
  
  # File upload configuration
  max_file_size = 52428800  # 50MB
  allowed_file_extensions = [
    ".pdf", ".txt", ".docx", ".doc", ".md", ".csv",
    ".jpg", ".jpeg", ".png", ".gif", ".bmp",
    ".mp3", ".wav", ".mp4", ".avi"
  ]
  
  # Upload configuration
  upload_chunk_size = 5242880  # 5MB chunks
  max_concurrent_uploads = 3
  upload_retry_attempts = 3
  upload_timeout_seconds = 300
  
  # Document processor configuration
  processor_replicas = 2
  processor_resources = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2"
      memory = "4Gi"
    }
  }
  
  # Auto-scaling configuration
  enable_processor_hpa = true
  processor_hpa_min_replicas = 1
  processor_hpa_max_replicas = 5
  processor_hpa_cpu_target = 70
  processor_hpa_memory_target = 80
  
  # AWS configuration (using IAM user credentials for example)
  enable_irsa = false
  aws_access_key_id = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
  
  # External service integration
  qdrant_url = "http://example-customer-qdrant.qdrant.svc.cluster.local:6333"
  qdrant_api_key = var.qdrant_api_key
  
  # Security settings
  enable_network_policy = false  # Simplified for example
  
  common_labels = {
    Environment = "development"
    Project     = "ai-assistant"
    Customer    = "example-customer"
  }
}

# Variables
variable "aws_access_key_id" {
  description = "AWS access key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key"
  type        = string
  sensitive   = true
}

variable "qdrant_api_key" {
  description = "Qdrant API key"
  type        = string
  sensitive   = true
  default     = ""
}

# Outputs
output "document_processor_endpoint" {
  description = "Document processor API endpoint"
  value       = module.s3_integration.document_processor_endpoint
}

output "s3_bucket_name" {
  description = "S3 bucket name used for document storage"
  value       = module.s3_integration.s3_bucket_name
}

output "processor_service_name" {
  description = "Document processor service name"
  value       = module.s3_integration.document_processor_service_name
}

output "integration_status" {
  description = "S3 integration configuration status"
  value       = module.s3_integration.integration_status
}

output "virus_scanning_enabled" {
  description = "Whether virus scanning is enabled"
  value       = module.s3_integration.virus_scanning_enabled
}

output "metadata_indexing_enabled" {
  description = "Whether metadata indexing is enabled"
  value       = module.s3_integration.metadata_indexing_enabled
}

output "max_file_size" {
  description = "Maximum allowed file size"
  value       = module.s3_integration.max_file_size
}

output "allowed_file_extensions" {
  description = "List of allowed file extensions"
  value       = module.s3_integration.allowed_file_extensions
}