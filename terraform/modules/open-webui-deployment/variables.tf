# Variables for Open WebUI Deployment Module

variable "customer_name" {
  description = "Name of the customer (used for resource naming)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.customer_name))
    error_message = "Customer name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "namespace" {
  description = "Kubernetes namespace for Open WebUI deployment"
  type        = string
  default     = "open-webui"
}

variable "open_webui_image" {
  description = "Open WebUI Docker image repository"
  type        = string
  default     = "ghcr.io/open-webui/open-webui"
}

variable "open_webui_version" {
  description = "Open WebUI version tag"
  type        = string
  default     = "main"
}

variable "replicas" {
  description = "Number of Open WebUI replicas"
  type        = number
  default     = 2
  validation {
    condition     = var.replicas >= 1 && var.replicas <= 10
    error_message = "Replicas must be between 1 and 10."
  }
}

variable "data_storage_size" {
  description = "Size of persistent storage for user data"
  type        = string
  default     = "10Gi"
}

variable "uploads_storage_size" {
  description = "Size of persistent storage for uploaded files"
  type        = string
  default     = "50Gi"
}

variable "storage_type" {
  description = "EBS volume type for Open WebUI storage"
  type        = string
  default     = "gp3"
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "Storage type must be one of: gp2, gp3, io1, io2."
  }
}

variable "resources" {
  description = "Resource requests and limits for Open WebUI containers"
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

# UI Configuration
variable "ui_title" {
  description = "Title for the Open WebUI interface"
  type        = string
  default     = "White Label AI Assistant"
}

variable "webui_url" {
  description = "External URL for the Open WebUI interface"
  type        = string
  default     = ""
}

variable "default_locale" {
  description = "Default locale for the UI"
  type        = string
  default     = "en-US"
}

variable "prompt_suggestions" {
  description = "List of prompt suggestions to display"
  type        = list(string)
  default = [
    "Help me write a professional email",
    "Explain a complex topic in simple terms",
    "Analyze this document for key insights",
    "Generate creative content ideas"
  ]
}

variable "default_models" {
  description = "List of default models to display"
  type        = list(string)
  default     = ["llama3.1:8b", "gpt-4", "claude-3-sonnet"]
}

variable "model_filter_enabled" {
  description = "Enable model filtering"
  type        = bool
  default     = true
}

variable "model_filter_list" {
  description = "List of allowed models (if filtering enabled)"
  type        = list(string)
  default     = []
}

# Service Integration Configuration
variable "ollama_base_urls" {
  description = "List of Ollama base URLs"
  type        = list(string)
  default     = []
}

variable "ollama_api_base_url" {
  description = "Primary Ollama API base URL"
  type        = string
  default     = ""
}

variable "openai_api_base_urls" {
  description = "List of OpenAI-compatible API base URLs"
  type        = list(string)
  default     = []
}

variable "litellm_api_base_url" {
  description = "LiteLLM API base URL"
  type        = string
  default     = ""
}

# Feature Flags
variable "enable_signup" {
  description = "Enable user signup"
  type        = bool
  default     = false
}

variable "enable_login_form" {
  description = "Enable login form"
  type        = bool
  default     = true
}

variable "enable_web_search" {
  description = "Enable web search functionality"
  type        = bool
  default     = false
}

variable "enable_image_generation" {
  description = "Enable image generation"
  type        = bool
  default     = false
}

variable "enable_community_sharing" {
  description = "Enable community sharing features"
  type        = bool
  default     = false
}

variable "enable_message_rating" {
  description = "Enable message rating"
  type        = bool
  default     = true
}

variable "enable_model_filter" {
  description = "Enable model filtering"
  type        = bool
  default     = true
}

# Authentication Configuration
variable "trusted_header_auth" {
  description = "Enable trusted header authentication"
  type        = bool
  default     = false
}

variable "auth_webhook_url" {
  description = "Authentication webhook URL"
  type        = string
  default     = ""
}

# RAG Configuration
variable "enable_rag_hybrid_search" {
  description = "Enable RAG hybrid search"
  type        = bool
  default     = true
}

variable "enable_rag_web_loader" {
  description = "Enable RAG web loader"
  type        = bool
  default     = false
}

variable "rag_chunk_size" {
  description = "RAG chunk size for document processing"
  type        = number
  default     = 1000
}

variable "rag_chunk_overlap" {
  description = "RAG chunk overlap for document processing"
  type        = number
  default     = 200
}

variable "qdrant_url" {
  description = "Qdrant vector database URL"
  type        = string
  default     = ""
}

variable "qdrant_collection_name" {
  description = "Qdrant collection name for embeddings"
  type        = string
  default     = "documents"
}

# S3 Storage Configuration
variable "enable_s3_storage" {
  description = "Enable S3 storage for documents"
  type        = bool
  default     = true
}

variable "s3_bucket_name" {
  description = "S3 bucket name for document storage"
  type        = string
  default     = ""
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

# Secrets
variable "jwt_secret" {
  description = "JWT secret for session management"
  type        = string
  sensitive   = true
  default     = ""
}

variable "database_url" {
  description = "Database connection URL"
  type        = string
  sensitive   = true
  default     = ""
}

variable "openai_api_key" {
  description = "OpenAI API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "litellm_api_key" {
  description = "LiteLLM API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "qdrant_api_key" {
  description = "Qdrant API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_access_key_id" {
  description = "AWS access key ID for S3 access"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_secret_access_key" {
  description = "AWS secret access key for S3 access"
  type        = string
  sensitive   = true
  default     = ""
}

variable "webhook_secret" {
  description = "Webhook secret for authentication"
  type        = string
  sensitive   = true
  default     = ""
}

# Kubernetes Configuration
variable "node_selector" {
  description = "Node selector for Open WebUI pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for Open WebUI pods"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = []
}

variable "enable_pod_anti_affinity" {
  description = "Enable pod anti-affinity to spread replicas across nodes"
  type        = bool
  default     = true
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# Backup Configuration
variable "backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Cron schedule for automated backups"
  type        = string
  default     = "0 2 * * *"  # Daily at 2 AM
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}# Networ
king Configuration
variable "enable_external_access" {
  description = "Enable external LoadBalancer service for Open WebUI"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Open WebUI external service"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "load_balancer_scheme" {
  description = "Load balancer scheme (internal or internet-facing)"
  type        = string
  default     = "internal"
  validation {
    condition     = contains(["internal", "internet-facing"], var.load_balancer_scheme)
    error_message = "Load balancer scheme must be either 'internal' or 'internet-facing'."
  }
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for HTTPS termination"
  type        = string
  default     = ""
}

variable "enable_ingress" {
  description = "Enable Kubernetes Ingress for Open WebUI"
  type        = bool
  default     = false
}

variable "ingress_hostname" {
  description = "Hostname for the ingress"
  type        = string
  default     = ""
}

variable "ingress_class" {
  description = "Ingress class to use"
  type        = string
  default     = "nginx"
}

variable "ingress_tls_enabled" {
  description = "Enable TLS for ingress"
  type        = bool
  default     = true
}

variable "cert_manager_issuer" {
  description = "Cert-manager cluster issuer for TLS certificates"
  type        = string
  default     = "letsencrypt-prod"
}

variable "enable_network_policy" {
  description = "Enable Kubernetes network policies"
  type        = bool
  default     = true
}

variable "service_annotations" {
  description = "Annotations for Open WebUI services"
  type        = map(string)
  default     = {}
}

variable "ingress_annotations" {
  description = "Annotations for Open WebUI ingress"
  type        = map(string)
  default     = {}
}

# Auto-scaling Configuration
variable "enable_hpa" {
  description = "Enable Horizontal Pod Autoscaler"
  type        = bool
  default     = false
}

variable "hpa_min_replicas" {
  description = "Minimum replicas for HPA"
  type        = number
  default     = 2
}

variable "hpa_max_replicas" {
  description = "Maximum replicas for HPA"
  type        = number
  default     = 10
}

variable "hpa_cpu_target" {
  description = "Target CPU utilization percentage for HPA"
  type        = number
  default     = 70
}

variable "hpa_memory_target" {
  description = "Target memory utilization percentage for HPA"
  type        = number
  default     = 80
}