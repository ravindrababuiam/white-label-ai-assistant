# Variables for Qdrant Deployment Module

variable "customer_name" {
  description = "Name of the customer (used for resource naming)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.customer_name))
    error_message = "Customer name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "namespace" {
  description = "Kubernetes namespace for Qdrant deployment"
  type        = string
  default     = "qdrant"
}

variable "qdrant_image" {
  description = "Qdrant Docker image repository"
  type        = string
  default     = "qdrant/qdrant"
}

variable "qdrant_version" {
  description = "Qdrant version tag"
  type        = string
  default     = "v1.7.4"
}

variable "replicas" {
  description = "Number of Qdrant replicas"
  type        = number
  default     = 1
  validation {
    condition     = var.replicas >= 1 && var.replicas <= 10
    error_message = "Replicas must be between 1 and 10."
  }
}

variable "storage_size" {
  description = "Size of persistent storage for Qdrant data"
  type        = string
  default     = "50Gi"
}

variable "storage_type" {
  description = "EBS volume type for Qdrant storage"
  type        = string
  default     = "gp3"
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "Storage type must be one of: gp2, gp3, io1, io2."
  }
}

variable "resources" {
  description = "Resource requests and limits for Qdrant containers"
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

variable "log_level" {
  description = "Log level for Qdrant"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["TRACE", "DEBUG", "INFO", "WARN", "ERROR"], var.log_level)
    error_message = "Log level must be one of: TRACE, DEBUG, INFO, WARN, ERROR."
  }
}

variable "max_request_size_mb" {
  description = "Maximum request size in MB"
  type        = number
  default     = 32
}

variable "wal_capacity_mb" {
  description = "Write-ahead log capacity in MB"
  type        = number
  default     = 32
}

variable "cluster_enabled" {
  description = "Enable Qdrant clustering"
  type        = bool
  default     = false
}

variable "telemetry_disabled" {
  description = "Disable Qdrant telemetry"
  type        = bool
  default     = true
}

variable "enable_authentication" {
  description = "Enable API key authentication for Qdrant"
  type        = bool
  default     = true
}

variable "api_key" {
  description = "API key for Qdrant authentication (required if enable_authentication is true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_external_access" {
  description = "Enable external LoadBalancer service for Qdrant"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Qdrant external service"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "enable_network_policy" {
  description = "Enable Kubernetes network policies"
  type        = bool
  default     = true
}

variable "enable_pod_anti_affinity" {
  description = "Enable pod anti-affinity to spread replicas across nodes"
  type        = bool
  default     = true
}

variable "node_selector" {
  description = "Node selector for Qdrant pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for Qdrant pods"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = []
}

variable "service_annotations" {
  description = "Annotations for Qdrant services"
  type        = map(string)
  default     = {}
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "collections_config" {
  description = "Configuration for Qdrant collections to be created"
  type = list(object({
    name           = string
    vector_size    = number
    distance       = string
    on_disk_payload = bool
    hnsw_config = object({
      m                = number
      ef_construct     = number
      full_scan_threshold = number
    })
  }))
  default = [
    {
      name           = "documents"
      vector_size    = 1536  # OpenAI embedding size
      distance       = "Cosine"
      on_disk_payload = true
      hnsw_config = {
        m                = 16
        ef_construct     = 100
        full_scan_threshold = 20000
      }
    }
  ]
}

variable "backup_enabled" {
  description = "Enable automated backups to S3"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Cron schedule for automated backups"
  type        = string
  default     = "0 2 * * *"  # Daily at 2 AM
}

variable "backup_s3_bucket" {
  description = "S3 bucket for storing Qdrant backups"
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster (required for IRSA)"
  type        = string
  default     = ""
}