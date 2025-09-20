# Open WebUI Deployment Module

This Terraform module deploys Open WebUI with custom configuration for the White Label AI Assistant platform, including integration with Ollama, LiteLLM, Qdrant, and S3 storage.

## Features

- **Custom Branding**: White-labeled interface with custom CSS and JavaScript
- **Multi-Model Support**: Integration with Ollama (local) and LiteLLM (external APIs)
- **Document Processing**: S3 integration for document storage and Qdrant for vector search
- **High Availability**: Multi-replica deployment with auto-scaling and load balancing
- **Data Persistence**: Persistent storage for user data and uploaded documents
- **Security**: Network policies, RBAC, and secure configuration management
- **Monitoring**: Health checks, metrics, and comprehensive logging
- **Backup & Recovery**: Automated backups to S3 with retention policies

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Open WebUI Architecture                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   Web UI Pod    │  │   Web UI Pod    │  │   Web UI Pod    │ │
│  │                 │  │                 │  │                 │ │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │ │
│  │ │ Open WebUI  │ │  │ │ Open WebUI  │ │  │ │ Open WebUI  │ │ │
│  │ │   Server    │ │  │ │   Server    │ │  │ │   Server    │ │ │
│  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │ │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │ │
│  │ │Backup Sidecar│ │  │ │Backup Sidecar│ │  │ │Backup Sidecar│ │
│  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │ │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │ │
│  │ │ Data PVC    │ │  │ │ Data PVC    │ │  │ │ Data PVC    │ │ │
│  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
          │                      │                      │
          │ Load Balancer        │ Ingress              │ Network Policy
          ▼                      ▼                      ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   External      │    │   Kubernetes    │    │   Security      │
│   Access        │    │   Ingress       │    │   Controls      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
          │                      │                      │
          │ Integration          │ Storage              │ Monitoring
          ▼                      ▼                      ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Ollama        │    │   S3 Storage    │    │   Health        │
│   LiteLLM       │    │   Database      │    │   Checks        │
│   Qdrant        │    │   EBS Volumes   │    │   Metrics       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Usage

### Basic Deployment

```hcl
module "open_webui" {
  source = "./modules/open-webui-deployment"

  customer_name = "acme-corp"
  namespace     = "open-webui"
  
  # UI Configuration
  ui_title    = "ACME AI Assistant"
  webui_url   = "https://ai.acme.com"
  
  # Service Integration
  ollama_api_base_url  = "http://acme-corp-ollama.ollama.svc.cluster.local:11434"
  litellm_api_base_url = "https://litellm.example.com"
  qdrant_url          = "http://acme-corp-qdrant.qdrant.svc.cluster.local:6333"
  
  # Storage Configuration
  enable_s3_storage = true
  s3_bucket_name   = "acme-corp-documents"
  s3_region        = "us-east-1"
  
  # Database Configuration
  database_url = "postgresql://user:pass@db.example.com:5432/openwebui"
  
  # Secrets
  jwt_secret      = var.jwt_secret
  litellm_api_key = var.litellm_api_key
  qdrant_api_key  = var.qdrant_api_key
  
  common_labels = {
    Environment = "production"
    Project     = "ai-assistant"
  }
}
```

### Production Deployment with High Availability

```hcl
module "open_webui_ha" {
  source = "./modules/open-webui-deployment"

  customer_name = "acme-corp"
  namespace     = "open-webui"
  replicas      = 3
  
  # UI Configuration
  ui_title         = "ACME AI Assistant"
  webui_url       = "https://ai.acme.com"
  default_locale  = "en-US"
  
  # Feature Configuration
  enable_signup              = false
  enable_web_search         = true
  enable_rag_hybrid_search  = true
  enable_message_rating     = true
  
  # Service Integration
  ollama_api_base_url  = "http://acme-corp-ollama.ollama.svc.cluster.local:11434"
  litellm_api_base_url = "https://litellm.example.com"
  qdrant_url          = "http://acme-corp-qdrant.qdrant.svc.cluster.local:6333"
  
  # Storage Configuration
  enable_s3_storage    = true
  s3_bucket_name      = "acme-corp-documents"
  data_storage_size   = "20Gi"
  uploads_storage_size = "100Gi"
  
  # High Availability
  enable_hpa              = true
  hpa_min_replicas       = 2
  hpa_max_replicas       = 10
  enable_pod_anti_affinity = true
  
  # External Access
  enable_external_access = true
  enable_ingress        = true
  ingress_hostname      = "ai.acme.com"
  ingress_tls_enabled   = true
  
  # Security
  enable_network_policy = true
  allowed_cidr_blocks  = ["10.0.0.0/8"]
  
  # Backup Configuration
  backup_enabled        = true
  backup_retention_days = 30
  
  # Resource Configuration
  resources = {
    requests = {
      cpu    = "1"
      memory = "2Gi"
    }
    limits = {
      cpu    = "4"
      memory = "8Gi"
    }
  }
  
  common_labels = {
    Environment = "production"
    Project     = "ai-assistant"
    Customer    = "acme-corp"
  }
}
```

### Development Deployment

```hcl
module "open_webui_dev" {
  source = "./modules/open-webui-deployment"

  customer_name = "dev-environment"
  namespace     = "open-webui-dev"
  replicas      = 1
  
  # UI Configuration
  ui_title = "AI Assistant (Development)"
  
  # Enable development features
  enable_signup = true
  enable_web_search = false
  
  # Local services
  ollama_api_base_url = "http://dev-ollama.ollama.svc.cluster.local:11434"
  
  # Simplified storage
  enable_s3_storage = false
  database_url     = "sqlite:///data/webui.db"
  
  # Minimal resources
  resources = {
    requests = {
      cpu    = "200m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "1"
      memory = "2Gi"
    }
  }
  
  # Disable production features
  enable_hpa           = false
  enable_network_policy = false
  backup_enabled       = false
  
  common_labels = {
    Environment = "development"
    Project     = "ai-assistant"
  }
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
| namespace | Kubernetes namespace | `string` | `"open-webui"` | no |
| open_webui_image | Open WebUI Docker image | `string` | `"ghcr.io/open-webui/open-webui"` | no |
| open_webui_version | Open WebUI version | `string` | `"main"` | no |
| replicas | Number of replicas | `number` | `2` | no |
| ui_title | UI title | `string` | `"White Label AI Assistant"` | no |
| ollama_api_base_url | Ollama API URL | `string` | `""` | no |
| litellm_api_base_url | LiteLLM API URL | `string` | `""` | no |
| qdrant_url | Qdrant URL | `string` | `""` | no |
| enable_s3_storage | Enable S3 storage | `bool` | `true` | no |
| database_url | Database connection URL | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| namespace | Kubernetes namespace |
| service_name | Service name |
| service_fqdn | Service FQDN |
| connection_string | HTTP connection string |
| deployment_name | Deployment name |
| ingress_name | Ingress name (if enabled) |

## Configuration

### UI Customization

The module includes custom CSS and JavaScript for white-label branding:

- **Custom CSS**: Brand colors, responsive design, accessibility features
- **Custom JavaScript**: Enhanced file upload, auto-save, keyboard shortcuts
- **Configurable UI**: Title, locale, prompt suggestions, model filters

### Service Integration

#### Ollama Integration
```hcl
ollama_api_base_url = "http://customer-ollama.ollama.svc.cluster.local:11434"
```

#### LiteLLM Integration
```hcl
litellm_api_base_url = "https://litellm.example.com"
litellm_api_key     = var.litellm_api_key
```

#### Qdrant Integration
```hcl
qdrant_url         = "http://customer-qdrant.qdrant.svc.cluster.local:6333"
qdrant_api_key     = var.qdrant_api_key
enable_rag_hybrid_search = true
```

#### S3 Integration
```hcl
enable_s3_storage     = true
s3_bucket_name       = "customer-documents"
aws_access_key_id    = var.aws_access_key_id
aws_secret_access_key = var.aws_secret_access_key
```

### Feature Flags

Control Open WebUI features through variables:

```hcl
enable_signup              = false  # User registration
enable_web_search         = true   # Web search functionality
enable_image_generation   = false  # Image generation
enable_rag_hybrid_search  = true   # RAG with vector search
enable_message_rating     = true   # Message feedback
```

### Security Configuration

#### Network Policies
```hcl
enable_network_policy = true
```

#### Authentication
```hcl
trusted_header_auth = false
auth_webhook_url   = "https://auth.example.com/webhook"
```

#### Access Control
```hcl
enable_external_access = true
allowed_cidr_blocks   = ["10.0.0.0/8", "192.168.0.0/16"]
```

## Storage

### Persistent Volumes

The module creates two persistent volumes:

1. **User Data**: Stores user profiles, chat history, settings
2. **Uploads**: Stores uploaded documents and files

### Database Support

Supports both SQLite and PostgreSQL:

```hcl
# SQLite (development)
database_url = "sqlite:///data/webui.db"

# PostgreSQL (production)
database_url = "postgresql://user:pass@host:5432/dbname"
```

## Backup & Recovery

### Automated Backups

The module includes automated backup functionality:

- **Schedule**: Configurable cron schedule (default: daily at 2 AM)
- **Retention**: Configurable retention period (default: 30 days)
- **Storage**: Backups stored in S3 with organized folder structure
- **Components**: User data, uploads, and database backups

### Backup Structure
```
s3://bucket/openwebui-backups/customer-name/YYYYMMDD_HHMMSS/
├── metadata/
│   └── backup_info.json
├── data/
│   └── user_data.tar.gz
├── uploads/
│   └── uploads.tar.gz
└── database/
    └── database.dump.gz
```

## Monitoring & Health Checks

### Health Check Script

Comprehensive health checking:

```bash
# Run health check
kubectl exec -n open-webui deployment/customer-open-webui -- python /scripts/health-check.py

# Get summary
kubectl exec -n open-webui deployment/customer-open-webui -- python /scripts/health-check.py --format summary
```

### Monitored Components

- Web interface responsiveness
- API endpoint availability
- Database connectivity
- External service integration (Ollama, LiteLLM, Qdrant)
- S3 storage access
- System resource usage

### Metrics

Prometheus metrics available at `/metrics` endpoint:

- HTTP request metrics
- Response time metrics
- Error rate metrics
- Resource utilization metrics

## Scaling

### Horizontal Pod Autoscaler

```hcl
enable_hpa        = true
hpa_min_replicas  = 2
hpa_max_replicas  = 10
hpa_cpu_target    = 70
hpa_memory_target = 80
```

### Pod Disruption Budget

Ensures availability during updates:

```hcl
# Automatically created when replicas > 1
# Maintains 50% minimum availability
```

## Troubleshooting

### Common Issues

1. **Pod startup failures**
   ```bash
   kubectl logs -n open-webui deployment/customer-open-webui -c init-db
   kubectl describe pod -n open-webui -l app.kubernetes.io/name=open-webui
   ```

2. **Database connection issues**
   ```bash
   kubectl exec -n open-webui deployment/customer-open-webui -- python /scripts/health-check.py --verbose
   ```

3. **Service integration problems**
   ```bash
   # Check service connectivity
   kubectl exec -n open-webui deployment/customer-open-webui -- curl -v http://ollama-service:11434/api/tags
   ```

### Useful Commands

```bash
# Port forward for local access
kubectl port-forward -n open-webui svc/customer-open-webui 8080:8080

# View logs
kubectl logs -n open-webui deployment/customer-open-webui -f

# Run manual backup
kubectl exec -n open-webui deployment/customer-open-webui -c backup-sidecar -- /scripts/backup-data.sh

# Scale deployment
kubectl scale -n open-webui deployment/customer-open-webui --replicas=5

# Check resource usage
kubectl top pods -n open-webui
```

## Integration Examples

### Complete Stack Integration

```hcl
# Deploy complete AI assistant stack
module "s3_storage" {
  source = "./modules/customer-s3"
  # ... configuration
}

module "qdrant" {
  source = "./modules/qdrant-deployment"
  # ... configuration
}

module "ollama" {
  source = "./modules/ollama-deployment"
  # ... configuration
}

module "open_webui" {
  source = "./modules/open-webui-deployment"
  
  # Integration with other modules
  ollama_api_base_url = module.ollama.connection_string
  qdrant_url         = module.qdrant.connection_string
  s3_bucket_name     = module.s3_storage.bucket_name
  
  # ... other configuration
}
```

This module provides a complete, production-ready Open WebUI deployment with comprehensive integration capabilities for the White Label AI Assistant platform.