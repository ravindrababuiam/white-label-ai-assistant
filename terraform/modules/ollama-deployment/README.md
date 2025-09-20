# Ollama Deployment Module

This Terraform module deploys Ollama for local LLM inference on Kubernetes with GPU support, automated model management, and persistent storage.

## Features

- **GPU Support**: Automatic GPU detection and allocation for accelerated inference
- **Model Management**: Automated model downloading, loading, and cleanup
- **Persistent Storage**: Dedicated storage for models with configurable size and type
- **High Availability**: Multi-replica deployment with pod anti-affinity
- **Auto-scaling**: Horizontal Pod Autoscaler based on CPU/memory usage
- **Health Monitoring**: Comprehensive health checks and model validation
- **Security**: Network policies, RBAC, and security contexts

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Open WebUI    │    │  Model Manager  │    │  Health Checks  │
│                 │    │   (Sidecar)     │    │                 │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          │ API Calls            │ Management           │ Monitoring
          │                      │                      │
          ▼                      ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Ollama Deployment                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │   Pod 0     │  │   Pod 1     │  │   Pod N     │            │
│  │             │  │             │  │             │            │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │            │
│  │ │Ollama   │ │  │ │Ollama   │ │  │ │Ollama   │ │            │
│  │ │Server   │ │  │ │Server   │ │  │ │Server   │ │            │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │            │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │            │
│  │ │  PVC    │ │  │ │  PVC    │ │  │ │  PVC    │ │            │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────────────────────────────────────────────────┘
          │                      │
          │ Model Storage        │ GPU Resources
          ▼                      ▼
┌─────────────────┐    ┌─────────────────┐
│   EBS Volumes   │    │  GPU Nodes      │
└─────────────────┘    └─────────────────┘
```

## Usage

### Basic CPU Deployment

```hcl
module "ollama" {
  source = "./modules/ollama-deployment"

  customer_name = "acme-corp"
  namespace     = "ollama"
  
  # Storage configuration
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

  # Default models to download
  default_models = [
    "llama3.1:8b",
    "nomic-embed-text",
    "codellama:7b"
  ]

  common_labels = {
    Environment = "production"
    Project     = "ai-assistant"
  }
}
```

### GPU-Enabled Deployment

```hcl
module "ollama_gpu" {
  source = "./modules/ollama-deployment"

  customer_name = "acme-corp"
  namespace     = "ollama"
  
  # Enable GPU support
  enable_gpu    = true
  gpu_count     = 1
  gpu_node_types = ["g4dn.xlarge", "g5.xlarge"]
  
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
    "mistral:7b"
  ]

  # Node selection for GPU nodes
  node_selector = {
    "node-type" = "gpu"
  }

  tolerations = [
    {
      key      = "nvidia.com/gpu"
      operator = "Exists"
      effect   = "NoSchedule"
    }
  ]
}
```

### High Availability with Auto-scaling

```hcl
module "ollama_ha" {
  source = "./modules/ollama-deployment"

  customer_name = "acme-corp"
  namespace     = "ollama"
  replicas      = 3
  
  # Enable auto-scaling
  enable_hpa        = true
  hpa_min_replicas  = 2
  hpa_max_replicas  = 10
  hpa_cpu_target    = 70
  hpa_memory_target = 80
  
  # High availability settings
  enable_pod_anti_affinity = true
  
  # Model configuration
  default_models = ["llama3.1:8b", "nomic-embed-text"]
  
  # Performance tuning
  max_loaded_models = 2
  num_parallel      = 8
  keep_alive        = "10m"
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| kubernetes | ~> 2.23 |

## Providers

| Name | Version |
|------|---------|
| kubernetes | ~> 2.23 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| customer_name | Name of the customer | `string` | n/a | yes |
| namespace | Kubernetes namespace | `string` | `"ollama"` | no |
| ollama_image | Ollama Docker image | `string` | `"ollama/ollama"` | no |
| ollama_version | Ollama version | `string` | `"latest"` | no |
| replicas | Number of replicas | `number` | `1` | no |
| model_storage_size | Model storage size | `string` | `"100Gi"` | no |
| storage_type | EBS volume type | `string` | `"gp3"` | no |
| enable_gpu | Enable GPU support | `bool` | `false` | no |
| gpu_count | Number of GPUs per pod | `number` | `1` | no |
| default_models | Default models to download | `list(string)` | `["llama3.1:8b", "nomic-embed-text"]` | no |
| resources | Resource requests/limits | `object` | See variables.tf | no |

## Outputs

| Name | Description |
|------|-------------|
| namespace | Kubernetes namespace |
| service_name | Service name |
| service_fqdn | Service FQDN |
| connection_string | API connection string |
| api_endpoint | API endpoint |
| api_port | API port |

## Model Management

### Automatic Model Downloads

The module automatically downloads specified models during initialization:

```hcl
default_models = [
  "llama3.1:8b",      # General purpose chat model
  "nomic-embed-text",  # Embedding model for RAG
  "codellama:7b",     # Code generation model
  "mistral:7b"        # Alternative chat model
]
```

### Model Configuration

Custom model configurations can be specified:

```hcl
model_configs = {
  "llama3.1:8b" = {
    parameters = {
      temperature = "0.7"
      top_p       = "0.9"
      top_k       = "40"
    }
    template = "{{ .System }}\n\n{{ .Prompt }}"
    system   = "You are a helpful AI assistant."
  }
}
```

### Model Lifecycle Management

The model manager sidecar container:

- **Monitors** model usage and performance
- **Loads/unloads** models based on demand
- **Cleans up** unused models automatically
- **Health checks** loaded models
- **Manages** memory usage efficiently

## GPU Support

### GPU Configuration

```hcl
# Enable GPU support
enable_gpu = true
gpu_count  = 1

# Specify GPU node types
gpu_node_types = [
  "g4dn.xlarge",   # NVIDIA T4
  "g4dn.2xlarge",  # NVIDIA T4
  "g5.xlarge",     # NVIDIA A10G
  "g5.2xlarge"     # NVIDIA A10G
]

# GPU memory management
gpu_memory_fraction = 0.9
```

### GPU Node Selection

```hcl
node_selector = {
  "node-type" = "gpu"
  "gpu-type"  = "nvidia"
}

tolerations = [
  {
    key      = "nvidia.com/gpu"
    operator = "Exists"
    effect   = "NoSchedule"
  }
]
```

## Performance Tuning

### Resource Configuration

```hcl
resources = {
  requests = {
    cpu    = "4"      # Minimum CPU cores
    memory = "8Gi"    # Minimum memory
  }
  limits = {
    cpu    = "16"     # Maximum CPU cores
    memory = "32Gi"   # Maximum memory
  }
}
```

### Ollama Configuration

```hcl
# Performance settings
max_loaded_models = 3      # Models to keep in memory
num_parallel      = 4      # Parallel request processing
max_queue        = 512     # Request queue size
keep_alive       = "5m"    # Model retention time

# GPU settings (if enabled)
gpu_memory_fraction = 0.9  # GPU memory usage
```

## Security Features

### Network Security
- Network policies restrict pod-to-pod communication
- Service mesh integration ready
- Internal-only LoadBalancer option
- CIDR-based access control

### Container Security
- Non-root container execution
- Read-only root filesystem
- Security context enforcement
- Capability dropping

### Resource Security
- RBAC with minimal permissions
- Service account isolation
- Secrets management for sensitive data

## Monitoring & Observability

### Health Checks
- **Startup probes** for initialization
- **Liveness probes** for container health
- **Readiness probes** for traffic routing
- **Custom health checks** for model validation

### Metrics
- Prometheus metrics endpoint
- Custom metrics for model performance
- Resource utilization monitoring
- Request/response metrics

### Logging
- Structured JSON logging
- Configurable log levels
- Model operation logging
- Performance metrics logging

## Troubleshooting

### Common Issues

1. **Models not downloading**
   ```bash
   # Check init container logs
   kubectl logs -n ollama deployment/customer-ollama -c model-downloader
   
   # Check available storage
   kubectl exec -n ollama deployment/customer-ollama -- df -h /models
   ```

2. **GPU not detected**
   ```bash
   # Check GPU availability
   kubectl describe nodes | grep nvidia.com/gpu
   
   # Check pod GPU allocation
   kubectl describe pod -n ollama -l app.kubernetes.io/name=ollama
   ```

3. **High memory usage**
   ```bash
   # Check model manager logs
   kubectl logs -n ollama deployment/customer-ollama -c model-manager
   
   # Manually trigger cleanup
   kubectl exec -n ollama deployment/customer-ollama -- /scripts/cleanup-models.sh
   ```

### Useful Commands

```bash
# Check Ollama status
kubectl exec -n ollama deployment/customer-ollama -- curl localhost:11434/api/tags

# List loaded models
kubectl exec -n ollama deployment/customer-ollama -- curl localhost:11434/api/ps

# Test model inference
kubectl exec -n ollama deployment/customer-ollama -- curl -X POST localhost:11434/api/generate \
  -d '{"model":"llama3.1:8b","prompt":"Hello","stream":false}'

# Port forward for local access
kubectl port-forward -n ollama svc/customer-ollama 11434:11434

# Scale deployment
kubectl scale -n ollama deployment/customer-ollama --replicas=3
```

## Integration

### Open WebUI Integration

```python
import requests

# Connect to Ollama service
ollama_url = "http://customer-ollama.ollama.svc.cluster.local:11434"

# List available models
response = requests.get(f"{ollama_url}/api/tags")
models = response.json()["models"]

# Generate text
payload = {
    "model": "llama3.1:8b",
    "prompt": "Explain quantum computing",
    "stream": False
}

response = requests.post(f"{ollama_url}/api/generate", json=payload)
result = response.json()["response"]
```

### External API Integration

```bash
# External access (if enabled)
OLLAMA_EXTERNAL_URL=$(kubectl get svc -n ollama customer-ollama-external -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -X POST http://$OLLAMA_EXTERNAL_URL:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3.1:8b","prompt":"Hello world","stream":false}'
```