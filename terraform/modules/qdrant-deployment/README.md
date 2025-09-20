# Qdrant Vector Database Deployment Module

This Terraform module deploys Qdrant vector database on Kubernetes using StatefulSets with persistent storage, automated backups, and collection initialization.

## Features

- **High Availability**: StatefulSet deployment with persistent storage
- **Security**: Network policies, RBAC, optional API key authentication
- **Backup & Recovery**: Automated S3 backups with retention policies
- **Monitoring**: Health checks, readiness probes, and metrics endpoints
- **Auto-scaling**: Horizontal pod autoscaling support
- **Collection Management**: Automated collection initialization with proper indexing

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Open WebUI    │    │   Backup Job    │    │  Init Job       │
│                 │    │                 │    │                 │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          │ HTTP/gRPC            │ Snapshots            │ Collections
          │                      │                      │
          ▼                      ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Qdrant StatefulSet                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │   Pod 0     │  │   Pod 1     │  │   Pod N     │            │
│  │             │  │             │  │             │            │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │            │
│  │ │   PVC   │ │  │ │   PVC   │ │  │ │   PVC   │ │            │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────────────────────────────────────────────────┘
          │                      │
          │ Persistent Storage   │ Backup Storage
          ▼                      ▼
┌─────────────────┐    ┌─────────────────┐
│   EBS Volumes   │    │   S3 Bucket     │
└─────────────────┘    └─────────────────┘
```

## Usage

### Basic Deployment

```hcl
module "qdrant" {
  source = "./modules/qdrant-deployment"

  customer_name = "acme-corp"
  namespace     = "qdrant"
  
  # Storage configuration
  storage_size = "100Gi"
  storage_type = "gp3"
  
  # Resource configuration
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

  # Collections configuration
  collections_config = [
    {
      name           = "documents"
      vector_size    = 1536
      distance       = "Cosine"
      on_disk_payload = true
      hnsw_config = {
        m                = 16
        ef_construct     = 100
        full_scan_threshold = 20000
      }
    }
  ]

  common_labels = {
    Environment = "production"
    Project     = "ai-assistant"
  }
}
```

### Production Deployment with Backup

```hcl
module "qdrant" {
  source = "./modules/qdrant-deployment"

  customer_name = "acme-corp"
  namespace     = "qdrant"
  replicas      = 3
  
  # Enable authentication
  enable_authentication = true
  api_key              = var.qdrant_api_key
  
  # Storage configuration
  storage_size = "500Gi"
  storage_type = "gp3"
  
  # Backup configuration
  backup_enabled        = true
  backup_s3_bucket     = "my-qdrant-backups"
  backup_schedule      = "0 2 * * *"  # Daily at 2 AM
  backup_retention_days = 30
  eks_cluster_name     = "my-eks-cluster"
  
  # Network security
  enable_network_policy = true
  enable_external_access = false
  
  # High availability
  enable_pod_anti_affinity = true
  
  node_selector = {
    "node-type" = "memory-optimized"
  }
  
  tolerations = [
    {
      key      = "dedicated"
      operator = "Equal"
      value    = "qdrant"
      effect   = "NoSchedule"
    }
  ]
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| kubernetes | ~> 2.23 |
| helm | ~> 2.11 |

## Providers

| Name | Version |
|------|---------|
| kubernetes | ~> 2.23 |
| helm | ~> 2.11 |
| aws | ~> 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| customer_name | Name of the customer | `string` | n/a | yes |
| namespace | Kubernetes namespace | `string` | `"qdrant"` | no |
| qdrant_image | Qdrant Docker image | `string` | `"qdrant/qdrant"` | no |
| qdrant_version | Qdrant version | `string` | `"v1.7.4"` | no |
| replicas | Number of replicas | `number` | `1` | no |
| storage_size | Storage size | `string` | `"50Gi"` | no |
| storage_type | EBS volume type | `string` | `"gp3"` | no |
| resources | Resource requests/limits | `object` | See variables.tf | no |
| enable_authentication | Enable API key auth | `bool` | `true` | no |
| api_key | API key for authentication | `string` | `""` | no |
| backup_enabled | Enable automated backups | `bool` | `true` | no |
| backup_s3_bucket | S3 bucket for backups | `string` | `""` | no |
| collections_config | Collections configuration | `list(object)` | See variables.tf | no |

## Outputs

| Name | Description |
|------|-------------|
| namespace | Kubernetes namespace |
| service_name | Service name |
| service_fqdn | Service FQDN |
| connection_string | HTTP connection string |
| grpc_connection_string | gRPC connection string |
| http_port | HTTP port |
| grpc_port | gRPC port |

## Collections

The module automatically creates collections based on the `collections_config` variable. Default configuration includes:

- **documents**: For document embeddings (1536 dimensions, Cosine distance)
- **conversations**: For conversation embeddings (1536 dimensions, Cosine distance)

Each collection includes optimized HNSW indexing and payload indexes for:
- `document_id` (keyword)
- `filename` (keyword)
- `content_type` (keyword)
- `upload_timestamp` (datetime)
- `customer_id` (keyword)
- `tags` (keyword)

## Backup Strategy

When backup is enabled, the module:

1. **Creates snapshots** of all collections daily
2. **Uploads to S3** with organized folder structure
3. **Retains backups** based on retention policy
4. **Creates manifests** with backup metadata
5. **Monitors backup jobs** with Kubernetes CronJobs

Backup folder structure:
```
s3://bucket/qdrant-backups/customer-name/YYYYMMDD_HHMMSS/
├── manifest.json
├── documents/
│   └── snapshot_YYYYMMDD_HHMMSS.snapshot
└── conversations/
    └── snapshot_YYYYMMDD_HHMMSS.snapshot
```

## Security Features

### Network Security
- Network policies restrict pod-to-pod communication
- Service mesh integration ready
- Internal LoadBalancer for external access
- CIDR-based access control

### Authentication & Authorization
- Optional API key authentication
- Kubernetes RBAC integration
- Service account with minimal permissions
- Secrets management for sensitive data

### Data Protection
- Encrypted persistent volumes
- Secure backup to S3 with IAM roles
- Read-only root filesystem
- Non-root container execution

## Monitoring & Observability

### Health Checks
- Liveness probes for container health
- Readiness probes for traffic routing
- Startup probes for initialization

### Metrics
- Prometheus metrics endpoint (`/metrics`)
- Custom metrics for business logic
- Resource utilization monitoring

### Logging
- Structured JSON logging
- Configurable log levels
- Integration with log aggregation systems

## Troubleshooting

### Common Issues

1. **Pod stuck in Pending**
   - Check storage class availability
   - Verify node resources
   - Check node selectors/tolerations

2. **Collections not created**
   - Check init job logs: `kubectl logs -n qdrant job/customer-qdrant-init`
   - Verify Qdrant service connectivity
   - Check API key configuration

3. **Backup failures**
   - Verify S3 bucket permissions
   - Check IRSA configuration
   - Review backup job logs

### Useful Commands

```bash
# Check Qdrant status
kubectl get pods -n qdrant -l app.kubernetes.io/name=qdrant

# View Qdrant logs
kubectl logs -n qdrant -l app.kubernetes.io/name=qdrant -f

# Check collections
kubectl exec -n qdrant deployment/qdrant-0 -- curl localhost:6333/collections

# Manual backup
kubectl create job -n qdrant manual-backup --from=cronjob/customer-qdrant-backup

# Port forward for local access
kubectl port-forward -n qdrant svc/customer-qdrant 6333:6333
```

## Integration

### Open WebUI Integration
```python
from qdrant_client import QdrantClient

client = QdrantClient(
    host="customer-qdrant.qdrant.svc.cluster.local",
    port=6333,
    api_key="your-api-key"  # if authentication enabled
)

# Search documents
results = client.search(
    collection_name="documents",
    query_vector=embedding,
    limit=10
)
```

### Backup Restoration
```bash
# Download backup
aws s3 cp s3://bucket/qdrant-backups/customer/backup.snapshot ./

# Restore collection
curl -X PUT "http://qdrant:6333/collections/documents/snapshots/upload" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @backup.snapshot
```