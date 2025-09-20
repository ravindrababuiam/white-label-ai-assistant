# Variables for Ollama Deployment Module

variable "customer_name" {
  description = "Name of the customer (used for resource naming)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.customer_name))
    error_message = "Customer name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "namespace" {
  description = "Kubernetes namespace for Ollama deployment"
  type        = string
  default     = "ollama"
}

variable "ollama_image" {
  description = "Ollama Docker image repository"
  type        = string
  default     = "ollama/ollama"
}

variable "ollama_version" {
  description = "Ollama version tag"
  type        = string
  default     = "latest"
}

variable "replicas" {
  description = "Number of Ollama replicas"
  type        = number
  default     = 1
  validation {
    condition     = var.replicas >= 1 && var.replicas <= 10
    error_message = "Replicas must be between 1 and 10."
  }
}

variable "model_storage_size" {
  description = "Size of persistent storage for Ollama models"
  type        = string
  default     = "100Gi"
}

variable "storage_type" {
  description = "EBS volume type for Ollama storage"
  type        = string
  default     = "gp3"
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "Storage type must be one of: gp2, gp3, io1, io2."
  }
}

variable "resources" {
  description = "Resource requests and limits for Ollama containers"
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
      cpu    = "2"
      memory = "4Gi"
    }
    limits = {
      cpu    = "8"
      memory = "16Gi"
    }
  }
}

variable "enable_gpu" {
  description = "Enable GPU support for Ollama"
  type        = bool
  default     = false
}

variable "gpu_count" {
  description = "Number of GPUs to allocate per pod"
  type        = number
  default     = 1
  validation {
    condition     = var.gpu_count >= 1 && var.gpu_count <= 8
    error_message = "GPU count must be between 1 and 8."
  }
}

variable "gpu_node_types" {
  description = "List of GPU-enabled node instance types"
  type        = list(string)
  default     = ["g4dn.xlarge", "g4dn.2xlarge", "g4dn.4xlarge", "g5.xlarge", "g5.2xlarge", "g5.4xlarge"]
}

variable "gpu_memory_fraction" {
  description = "Fraction of GPU memory to use (0.0-1.0)"
  type        = number
  default     = 0.9
  validation {
    condition     = var.gpu_memory_fraction > 0 && var.gpu_memory_fraction <= 1
    error_message = "GPU memory fraction must be between 0 and 1."
  }
}

variable "log_level" {
  description = "Log level for Ollama"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR."
  }
}

variable "max_loaded_models" {
  description = "Maximum number of models to keep loaded in memory"
  type        = number
  default     = 3
}

variable "num_parallel" {
  description = "Number of parallel requests to process"
  type        = number
  default     = 4
}

variable "max_queue" {
  description = "Maximum number of requests to queue"
  type        = number
  default     = 512
}

variable "keep_alive" {
  description = "How long to keep models loaded (e.g., '5m', '1h')"
  type        = string
  default     = "5m"
}

variable "default_models" {
  description = "List of default models to download on startup"
  type        = list(string)
  default     = ["llama3.1:8b", "nomic-embed-text"]
}

variable "model_configs" {
  description = "Configuration for specific models"
  type = map(object({
    parameters = map(string)
    template   = string
    system     = string
  }))
  default = {}
}

variable "enable_external_access" {
  description = "Enable external LoadBalancer service for Ollama"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Ollama external service"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "enable_network_policy" {
  description = "Enable Kubernetes network policies"
  type        = bool
  default     = true
}

variable "enable_clustering" {
  description = "Enable clustering support (creates headless service)"
  type        = bool
  default     = false
}

variable "enable_pod_anti_affinity" {
  description = "Enable pod anti-affinity to spread replicas across nodes"
  type        = bool
  default     = true
}

variable "enable_hpa" {
  description = "Enable Horizontal Pod Autoscaler"
  type        = bool
  default     = false
}

variable "hpa_min_replicas" {
  description = "Minimum replicas for HPA"
  type        = number
  default     = 1
}

variable "hpa_max_replicas" {
  description = "Maximum replicas for HPA"
  type        = number
  default     = 5
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

variable "node_selector" {
  description = "Node selector for Ollama pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for Ollama pods"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = []
}

variable "service_annotations" {
  description = "Annotations for Ollama services"
  type        = map(string)
  default     = {}
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "model_download_timeout" {
  description = "Timeout for model downloads in seconds"
  type        = number
  default     = 3600  # 1 hour
}

variable "enable_model_caching" {
  description = "Enable model caching between pod restarts"
  type        = bool
  default     = true
}

variable "model_cache_size" {
  description = "Size of model cache storage"
  type        = string
  default     = "50Gi"
}

variable "enable_metrics" {
  description = "Enable Prometheus metrics collection"
  type        = bool
  default     = true
}

variable "metrics_port" {
  description = "Port for metrics endpoint"
  type        = number
  default     = 9090
}