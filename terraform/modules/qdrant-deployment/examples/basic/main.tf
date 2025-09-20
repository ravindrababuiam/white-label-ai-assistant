# Example: Basic Qdrant deployment

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

# Basic Qdrant deployment
module "qdrant" {
  source = "../../"

  customer_name = "example-customer"
  namespace     = "qdrant"
  
  # Basic configuration
  replicas     = 1
  storage_size = "50Gi"
  storage_type = "gp3"
  
  # Resource configuration
  resources = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2"
      memory = "4Gi"
    }
  }

  # Collections for document embeddings
  collections_config = [
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

  # Security
  enable_authentication = false  # Simplified for example
  enable_network_policy = false
  
  # Disable backup for basic example
  backup_enabled = false

  common_labels = {
    Environment = "development"
    Project     = "ai-assistant"
    Customer    = "example-customer"
  }
}

# Outputs
output "qdrant_connection_string" {
  description = "Qdrant HTTP connection string"
  value       = module.qdrant.connection_string
}

output "qdrant_grpc_connection" {
  description = "Qdrant gRPC connection string"
  value       = module.qdrant.grpc_connection_string
}

output "qdrant_namespace" {
  description = "Kubernetes namespace"
  value       = module.qdrant.namespace
}