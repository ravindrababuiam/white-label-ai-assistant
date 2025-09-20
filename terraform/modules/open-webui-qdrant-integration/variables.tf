# Variables for Open WebUI Qdrant Integration Module

variable "customer_name" {
  description = "Name of the customer (used for resource naming)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.customer_name))
    error_message = "Customer name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "namespace" {
  description = "Kubernetes namespace for Qdrant integration deployment"
  type        = string
  default     = "open-webui"
}

# Qdrant Configuration
variable "qdrant_url" {
  description = "Qdrant server URL"
  type        = string
}

variable "qdrant_api_key" {
  description = "Qdrant API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "collection_name" {
  description = "Qdrant collection name for document embeddings"
  type        = string
  default     = "documents"
}

variable "vector_size" {
  description = "Size of embedding vectors"
  type        = number
  default     = 1536  # OpenAI embedding size
  validation {
    condition     = var.vector_size > 0 && var.vector_size <= 4096
    error_message = "Vector size must be between 1 and 4096."
  }
}

variable "distance_metric" {
  description = "Distance metric for vector similarity"
  type        = string
  default     = "Cosine"
  validation {
    condition     = contains(["Cosine", "Euclidean", "Dot"], var.distance_metric)
    error_message = "Distance metric must be one of: Cosine, Euclidean, Dot."
  }
}

variable "qdrant_timeout" {
  description = "Qdrant operation timeout in seconds"
  type        = number
  default     = 30
}

variable "max_retries" {
  description = "Maximum number of retries for Qdrant operations"
  type        = number
  default     = 3
}

variable "batch_size" {
  description = "Batch size for Qdrant operations"
  type        = number
  default     = 100
}

variable "enable_compression" {
  description = "Enable compression for Qdrant communication"
  type        = bool
  default     = true
}

# Embedding Configuration
variable "embedding_provider" {
  description = "Embedding provider (openai, huggingface, local)"
  type        = string
  default     = "openai"
  validation {
    condition     = contains(["openai", "huggingface", "local", "ollama"], var.embedding_provider)
    error_message = "Embedding provider must be one of: openai, huggingface, local, ollama."
  }
}

variable "embedding_model" {
  description = "Embedding model name"
  type        = string
  default     = "text-embedding-ada-002"
}

variable "embedding_api_url" {
  description = "Embedding API base URL"
  type        = string
  default     = ""
}

variable "embedding_api_key" {
  description = "Embedding API key"
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

variable "huggingface_api_key" {
  description = "Hugging Face API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "max_embedding_tokens" {
  description = "Maximum tokens for embedding generation"
  type        = number
  default     = 8192
}

variable "normalize_embeddings" {
  description = "Normalize embeddings to unit vectors"
  type        = bool
  default     = true
}

# Text Processing Configuration
variable "text_chunk_size" {
  description = "Size of text chunks for embedding"
  type        = number
  default     = 1000
}

variable "text_chunk_overlap" {
  description = "Overlap between text chunks"
  type        = number
  default     = 200
}

# Search Configuration
variable "default_search_limit" {
  description = "Default number of search results to return"
  type        = number
  default     = 10
}

variable "max_search_limit" {
  description = "Maximum number of search results allowed"
  type        = number
  default     = 100
}

variable "score_threshold" {
  description = "Minimum similarity score threshold for search results"
  type        = number
  default     = 0.7
}

variable "enable_hybrid_search" {
  description = "Enable hybrid search (vector + keyword)"
  type        = bool
  default     = true
}

variable "enable_reranking" {
  description = "Enable result reranking"
  type        = bool
  default     = false
}

variable "rerank_top_k" {
  description = "Number of top results to rerank"
  type        = number
  default     = 20
}

# Indexing Configuration
variable "auto_index_documents" {
  description = "Automatically index uploaded documents"
  type        = bool
  default     = true
}

variable "index_batch_size" {
  description = "Batch size for document indexing"
  type        = number
  default     = 50
}

variable "index_timeout" {
  description = "Timeout for indexing operations in seconds"
  type        = number
  default     = 300
}

variable "update_existing_documents" {
  description = "Update existing documents when reindexing"
  type        = bool
  default     = true
}

variable "extract_keywords" {
  description = "Extract keywords from documents for hybrid search"
  type        = bool
  default     = true
}

# Cache Configuration
variable "enable_embedding_cache" {
  description = "Enable caching of embeddings"
  type        = bool
  default     = true
}

variable "cache_ttl_seconds" {
  description = "Cache TTL in seconds"
  type        = number
  default     = 3600
}

variable "max_cache_size" {
  description = "Maximum cache size in MB"
  type        = number
  default     = 1024
}

# Service Configuration
variable "embedding_service_image" {
  description = "Embedding service Docker image"
  type        = string
  default     = "python"
}

variable "embedding_service_version" {
  description = "Embedding service image version"
  type        = string
  default     = "3.11-slim"
}

variable "search_service_image" {
  description = "Search service Docker image"
  type        = string
  default     = "python"
}

variable "search_service_version" {
  description = "Search service image version"
  type        = string
  default     = "3.11-slim"
}

variable "embedding_service_replicas" {
  description = "Number of embedding service replicas"
  type        = number
  default     = 2
}

variable "search_service_replicas" {
  description = "Number of search service replicas"
  type        = number
  default     = 2
}

# Resource Configuration
variable "embedding_service_resources" {
  description = "Resource requests and limits for embedding service"
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

variable "search_service_resources" {
  description = "Resource requests and limits for search service"
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
      cpu    = "300m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "1"
      memory = "2Gi"
    }
  }
}

# Auto-scaling Configuration
variable "enable_embedding_hpa" {
  description = "Enable HPA for embedding service"
  type        = bool
  default     = true
}

variable "embedding_hpa_min_replicas" {
  description = "Minimum replicas for embedding service HPA"
  type        = number
  default     = 1
}

variable "embedding_hpa_max_replicas" {
  description = "Maximum replicas for embedding service HPA"
  type        = number
  default     = 10
}

variable "embedding_hpa_cpu_target" {
  description = "Target CPU utilization for embedding service HPA"
  type        = number
  default     = 70
}

variable "embedding_hpa_memory_target" {
  description = "Target memory utilization for embedding service HPA"
  type        = number
  default     = 80
}

variable "enable_search_hpa" {
  description = "Enable HPA for search service"
  type        = bool
  default     = true
}

variable "search_hpa_min_replicas" {
  description = "Minimum replicas for search service HPA"
  type        = number
  default     = 1
}

variable "search_hpa_max_replicas" {
  description = "Maximum replicas for search service HPA"
  type        = number
  default     = 10
}

variable "search_hpa_cpu_target" {
  description = "Target CPU utilization for search service HPA"
  type        = number
  default     = 70
}

variable "search_hpa_memory_target" {
  description = "Target memory utilization for search service HPA"
  type        = number
  default     = 80
}

# Kubernetes Configuration
variable "node_selector" {
  description = "Node selector for Qdrant integration pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for Qdrant integration pods"
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

# Additional Service Configuration
variable "indexer_service_image" {
  description = "Document indexer service Docker image"
  type        = string
  default     = "python"
}

variable "indexer_service_version" {
  description = "Document indexer service image version"
  type        = string
  default     = "3.11-slim"
}

variable "search_api_image" {
  description = "Search API service Docker image"
  type        = string
  default     = "python"
}

variable "search_api_version" {
  description = "Search API service image version"
  type        = string
  default     = "3.11-slim"
}

variable "indexer_service_replicas" {
  description = "Number of document indexer service replicas"
  type        = number
  default     = 1
}

variable "search_api_replicas" {
  description = "Number of search API service replicas"
  type        = number
  default     = 2
}

# S3 Configuration for Document Storage
variable "s3_endpoint" {
  description = "S3 endpoint URL"
  type        = string
  default     = ""
}

variable "s3_bucket" {
  description = "S3 bucket name for document storage"
  type        = string
  default     = ""
}

# RAG Configuration
variable "enable_rag" {
  description = "Enable RAG (Retrieval Augmented Generation) functionality"
  type        = bool
  default     = true
}

variable "rag_context_window" {
  description = "Maximum context window size for RAG in characters"
  type        = number
  default     = 4000
}

variable "rag_max_chunks" {
  description = "Maximum number of context chunks for RAG"
  type        = number
  default     = 5
}

# Resource Configuration for Additional Services
variable "indexer_service_resources" {
  description = "Resource requests and limits for document indexer service"
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

variable "search_api_resources" {
  description = "Resource requests and limits for search API service"
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
      cpu    = "300m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "1"
      memory = "2Gi"
    }
  }
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}