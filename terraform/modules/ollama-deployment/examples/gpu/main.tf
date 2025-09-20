# Example: GPU-enabled Ollama deployment

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

# GPU-enabled Ollama deployment
module "ollama_gpu" {
  source = "../../"

  customer_name = "example-customer"
  namespace     = "ollama"
  
  # GPU configuration
  enable_gpu     = true
  gpu_count      = 1
  gpu_node_types = ["g4dn.xlarge", "g4dn.2xlarge", "g5.xlarge", "g5.2xlarge"]
  
  # Larger storage for GPU models
  model_storage_size = "500Gi"
  storage_type       = "gp3"
  
  # GPU-optimized resources
  resources = {
    requests = {
      cpu    = "4"
      memory = "16Gi"
    }
    limits = {
      cpu    = "16"
      memory = "64Gi"
    }
  }

  # GPU-suitable models
  default_models = [
    "llama3.1:70b",
    "codellama:34b",
    "mistral:7b",
    "nomic-embed-text"
  ]

  # Model configurations for GPU optimization
  model_configs = {
    "llama3.1:70b" = {
      parameters = {
        num_gpu = "1"
        num_thread = "8"
      }
      template = "{{ .System }}\n\n{{ .Prompt }}"
      system   = "You are a helpful AI assistant optimized for GPU inference."
    }
  }

  # Performance settings for GPU
  max_loaded_models   = 2
  num_parallel        = 8
  keep_alive         = "10m"
  gpu_memory_fraction = 0.9

  # Node selection for GPU nodes
  node_selector = {
    "node-type" = "gpu"
    "gpu-type"  = "nvidia"
  }

  tolerations = [
    {
      key      = "nvidia.com/gpu"
      operator = "Exists"
      value    = ""
      effect   = "NoSchedule"
    },
    {
      key      = "dedicated"
      operator = "Equal"
      value    = "gpu"
      effect   = "NoSchedule"
    }
  ]

  # Security and networking
  enable_network_policy = true
  enable_external_access = false

  common_labels = {
    Environment = "production"
    Project     = "ai-assistant"
    Customer    = "example-customer"
    Workload    = "gpu-inference"
  }
}

# Outputs
output "ollama_connection_string" {
  description = "Ollama API connection string"
  value       = module.ollama_gpu.connection_string
}

output "gpu_enabled" {
  description = "GPU support enabled"
  value       = module.ollama_gpu.gpu_enabled
}

output "gpu_count" {
  description = "Number of GPUs per pod"
  value       = module.ollama_gpu.gpu_count
}

output "model_storage_size" {
  description = "Model storage size"
  value       = module.ollama_gpu.model_storage_size
}