# Example: Basic Ollama deployment

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Basic Ollama deployment
module "ollama" {
  source = "../../"

  customer_name = "example-customer"
  namespace     = "ollama"
  
  # Basic configuration
  replicas           = 1
  model_storage_size = "100Gi"
  storage_type       = "gp3"
  
  # Resource configuration
  resources = {
    requests = {
      cpu    = "2"
      memory = "4Gi"
    }
    limits = {
      cpu    = "8"
      memory = "16Gi"
    }
  }

  # Default models for basic usage
  default_models = [
    "llama3.1:8b",
    "nomic-embed-text"
  ]

  # Performance settings
  max_loaded_models = 2
  num_parallel      = 4
  keep_alive        = "5m"

  # Security settings
  enable_network_policy = false  # Simplified for example
  enable_external_access = false

  common_labels = {
    Environment = "development"
    Project     = "ai-assistant"
    Customer    = "example-customer"
  }
}

# Outputs
output "ollama_connection_string" {
  description = "Ollama API connection string"
  value       = module.ollama.connection_string
}

output "ollama_api_endpoint" {
  description = "Ollama API endpoint"
  value       = module.ollama.api_endpoint
}

output "ollama_namespace" {
  description = "Kubernetes namespace"
  value       = module.ollama.namespace
}

output "default_models" {
  description = "Default models configured"
  value       = module.ollama.default_models
}