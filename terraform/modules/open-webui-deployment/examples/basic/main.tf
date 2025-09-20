# Example: Basic Open WebUI deployment

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

# Basic Open WebUI deployment
module "open_webui" {
  source = "../../"

  customer_name = "example-customer"
  namespace     = "open-webui"
  
  # Basic configuration
  replicas = 2
  
  # UI Configuration
  ui_title       = "Example AI Assistant"
  default_locale = "en-US"
  
  # Feature configuration
  enable_signup             = false
  enable_web_search        = false
  enable_rag_hybrid_search = true
  enable_message_rating    = true
  
  # Service integration (using placeholder URLs)
  ollama_api_base_url  = "http://example-customer-ollama.ollama.svc.cluster.local:11434"
  qdrant_url          = "http://example-customer-qdrant.qdrant.svc.cluster.local:6333"
  
  # Storage configuration
  enable_s3_storage    = false  # Simplified for example
  data_storage_size   = "10Gi"
  uploads_storage_size = "20Gi"
  
  # Database configuration (SQLite for simplicity)
  database_url = "sqlite:///data/webui.db"
  
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

  # Security configuration
  enable_network_policy = false  # Simplified for example
  enable_external_access = false
  
  # Backup configuration
  backup_enabled = false  # Simplified for example
  
  # Secrets (in production, use proper secret management)
  jwt_secret = "example-jwt-secret-change-in-production"
  
  common_labels = {
    Environment = "development"
    Project     = "ai-assistant"
    Customer    = "example-customer"
  }
}

# Outputs
output "open_webui_connection_string" {
  description = "Open WebUI HTTP connection string"
  value       = module.open_webui.connection_string
}

output "open_webui_namespace" {
  description = "Kubernetes namespace"
  value       = module.open_webui.namespace
}

output "open_webui_service_name" {
  description = "Service name"
  value       = module.open_webui.service_name
}

output "ui_title" {
  description = "UI title"
  value       = module.open_webui.ui_title
}