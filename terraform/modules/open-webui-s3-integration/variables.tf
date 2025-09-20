# Variables for Open WebUI S3 Integration Module

variable "customer_name" {
  description = "Name of the customer (used for resource naming)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.customer_name))
    error_message = "Customer name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "namespace" {
  description = "Kubernetes namespace for S3 integration deployment"
  type        = string
  default     = "open-webui"
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "S3 bucket name for document storage"
  type        = string
}

variable "s3_region" {
  description = "S3 bucket region"
  type        = string
  default     = "us-east-1"
}

variable "s3_endpoint" {
  description = "S3 endpoint URL (for S3-compatible storage)"
  type        = string
  default     = ""
}

variable "s3_use_ssl" {
  description = "Use SSL for S3 connections"
  type        = bool
  default     = true
}

variable "s3_path_style_access" {
  description = "Use path-style access for S3"
  type        = bool
  default     = false
}

variable "presigned_url_expiry" {
  description = "Expiry time for presigned URLs in seconds"
  type        = number
  default     = 3600
}

# File Upload Configuration
variable "max_file_size" {
  description = "Maximum file size in bytes"
  type        = number
  default     = 104857600  # 100MB
}

variable "allowed_file_extensions" {
  description = "List of allowed file extensions"
  type        = list(string)
  default = [
    ".pdf", ".txt", ".docx", ".doc", ".pptx", ".ppt", ".xlsx", ".xls",
    ".md", ".csv", ".json", ".xml", ".html", ".htm", ".rtf", ".odt",
    ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp",
    ".mp3", ".wav", ".mp4", ".avi", ".mov", ".wmv", ".flv"
  ]
}

variable "upload_chunk_size" {
  description = "Upload chunk size in bytes"
  type        = number
  default     = 5242880  # 5MB
}

variable "max_concurrent_uploads" {
  description = "Maximum number of concurrent uploads"
  type        = number
  default     = 3
}

variable "upload_retry_attempts" {
  description = "Number of retry attempts for failed uploads"
  type        = number
  default     = 3
}

variable "upload_timeout_seconds" {
  description = "Upload timeout in seconds"
  type        = number
  default     = 300
}

# Security Configuration
variable "enable_virus_scanning" {
  description = "Enable virus scanning for uploaded files"
  type        = bool
  default     = true
}

variable "enable_content_type_validation" {
  description = "Enable content type validation"
  type        = bool
  default     = true
}

variable "enable_filename_sanitization" {
  description = "Enable filename sanitization"
  type        = bool
  default     = true
}

variable "quarantine_suspicious_files" {
  description = "Quarantine suspicious files instead of rejecting"
  type        = bool
  default     = true
}

variable "virus_scan_timeout" {
  description = "Virus scan timeout in seconds"
  type        = number
  default     = 60
}

# Metadata and Indexing Configuration
variable "enable_metadata_indexing" {
  description = "Enable metadata extraction and indexing"
  type        = bool
  default     = true
}

variable "extract_text_content" {
  description = "Extract text content from documents"
  type        = bool
  default     = true
}

variable "generate_thumbnails" {
  description = "Generate thumbnails for supported file types"
  type        = bool
  default     = true
}

variable "extract_file_metadata" {
  description = "Extract file metadata (EXIF, document properties, etc.)"
  type        = bool
  default     = true
}

variable "enable_ocr" {
  description = "Enable OCR for image and PDF files"
  type        = bool
  default     = false
}

# Document Processor Configuration
variable "document_processor_image" {
  description = "Document processor Docker image"
  type        = string
  default     = "python"
}

variable "document_processor_version" {
  description = "Document processor image version"
  type        = string
  default     = "3.11-slim"
}

variable "processor_replicas" {
  description = "Number of document processor replicas"
  type        = number
  default     = 2
}

variable "processor_resources" {
  description = "Resource requests and limits for document processor"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2"
      memory = "4Gi"
    }
  }
}

# Auto-scaling Configuration
variable "enable_processor_hpa" {
  description = "Enable HPA for document processor"
  type        = bool
  default     = true
}

variable "processor_hpa_min_replicas" {
  description = "Minimum replicas for processor HPA"
  type        = number
  default     = 1
}

variable "processor_hpa_max_replicas" {
  description = "Maximum replicas for processor HPA"
  type        = number
  default     = 10
}

variable "processor_hpa_cpu_target" {
  description = "Target CPU utilization for processor HPA"
  type        = number
  default     = 70
}

variable "processor_hpa_memory_target" {
  description = "Target memory utilization for processor HPA"
  type        = number
  default     = 80
}

# AWS Configuration
variable "aws_access_key_id" {
  description = "AWS access key ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_secret_access_key" {
  description = "AWS secret access key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (IRSA)"
  type        = bool
  default     = true
}

variable "eks_cluster_name" {
  description = "EKS cluster name (required for IRSA)"
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 encryption"
  type        = string
  default     = ""
}

# Encryption Configuration
variable "s3_encryption_key" {
  description = "S3 client-side encryption key"
  type        = string
  sensitive   = true
  default     = ""
}

# External Service Integration
variable "virus_scan_api_key" {
  description = "API key for virus scanning service"
  type        = string
  sensitive   = true
  default     = ""
}

variable "qdrant_url" {
  description = "Qdrant vector database URL for metadata indexing"
  type        = string
  default     = ""
}

variable "qdrant_api_key" {
  description = "Qdrant API key"
  type        = string
  sensitive   = true
  default     = ""
}

# Kubernetes Configuration
variable "node_selector" {
  description = "Node selector for document processor pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for document processor pods"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = []
}

variable "enable_network_policy" {
  description = "Enable Kubernetes network policies"
  type        = bool
  default     = true
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}