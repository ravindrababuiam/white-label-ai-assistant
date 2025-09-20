# White Label AI Assistant Helm Charts

This directory contains Helm charts for deploying the white-label AI assistant customer stack to AWS EKS clusters.

## 🚀 Quick Start

### Deploy Customer Stack
```bash
# Basic deployment
./deploy-helm-chart.ps1 -CustomerName "acme-corp" -Environment "production"

# GPU-enabled deployment
./deploy-helm-chart.ps1 -CustomerName "tech-startup" -Environment "production" -EnableGpu

# Dry run validation
./deploy-helm-chart.ps1 -CustomerName "test-customer" -DryRun
```

### Using Helm Directly
```bash
# Install with default values
helm install customer-xyz helm-charts/customer-stack \
  --namespace customer-xyz-stack \
  --create-namespace \
  --set global.customerName=customer-xyz

# Install with production values
helm install customer-abc helm-charts/customer-stack \
  --namespace customer-abc-stack \
  --create-namespace \
  --values helm-charts/customer-stack/values-production.yaml \
  --set global.customerName=customer-abc
```

## 📋 Chart Structure

```
helm-charts/customer-stack/
├── Chart.yaml                           # Chart metadata
├── values.yaml                          # Default values
├── values-production.yaml               # Production overrides
├── values-gpu.yaml                      # GPU-enabled overrides
└── templates/
    ├── _helpers.tpl                     # Template helpers
    ├── namespace.yaml                   # Namespace creation
    ├── serviceaccount.yaml              # AWS IAM service account
    ├── secrets.yaml                     # Application secrets
    ├── configmaps.yaml                  # Configuration maps
    ├── open-webui-deployment.yaml       # Open WebUI deployment
    ├── open-webui-service.yaml          # Open WebUI service
    ├── open-webui-pvc.yaml              # Open WebUI storage
    ├── ollama-deployment.yaml           # Ollama deployment
    ├── ollama-service.yaml              # Ollama service
    ├── ollama-pvc.yaml                  # Ollama storage
    ├── ollama-model-init-job.yaml       # Model initialization
    ├── qdrant-statefulset.yaml          # Qdrant vector database
    ├── qdrant-service.yaml              # Qdrant service
    ├── qdrant-collection-init-job.yaml  # Collection initialization
    ├── pod-disruption-budget.yaml       # High availability
    ├── hpa.yaml                         # Auto-scaling
    └── network-policy.yaml              # Network security
```

## ⚙️ Configuration

### Global Values
```yaml
global:
  customerName: "customer-name"          # Customer identifier
  environment: "production"              # Environment type
  region: "us-west-2"                   # AWS region
  aws:
    accountId: "123456789012"           # AWS account ID
    region: "us-west-2"                 # AWS region
```

### AWS Integration
```yaml
aws:
  s3:
    enabled: true
    buckets:
      documents: "customer-documents-bucket"
      data: "customer-data-bucket"
    region: "us-west-2"
    
  rds:
    enabled: true
    endpoints:
      litellm: "litellm-db.region.rds.amazonaws.com"
      lago: "lago-db.region.rds.amazonaws.com"
    port: 5432
    
  elasticache:
    enabled: true
    endpoints:
      litellm: "litellm-redis.cache.amazonaws.com"
      lago: "lago-redis.cache.amazonaws.com"
    port: 6379
    
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/CustomerRole"
```

### Component Configuration

#### Open WebUI
```yaml
openWebUI:
  enabled: true
  replicaCount: 2
  image:
    repository: "ghcr.io/open-webui/open-webui"
    tag: "main"
  service:
    type: LoadBalancer
    port: 8080
  persistence:
    enabled: true
    size: "10Gi"
    storageClass: "gp3"
```

#### Ollama
```yaml
ollama:
  enabled: true
  replicaCount: 1
  image:
    repository: "ollama/ollama"
    tag: "latest"
  gpu:
    enabled: false  # Set to true for GPU support
  persistence:
    enabled: true
    size: "100Gi"
    storageClass: "gp3"
  models:
    preload:
      - "llama3.1:8b"
      - "nomic-embed-text"
```

#### Qdrant
```yaml
qdrant:
  enabled: true
  replicaCount: 1
  image:
    repository: "qdrant/qdrant"
    tag: "latest"
  persistence:
    enabled: true
    size: "50Gi"
    storageClass: "gp3"
  collections:
    init:
      enabled: true
      collections:
        - name: "documents"
          vector_size: 768
          distance: "Cosine"
```

## 🔧 Deployment Scenarios

### 1. Basic Production Deployment
```bash
helm install customer-prod helm-charts/customer-stack \
  --namespace customer-prod-stack \
  --create-namespace \
  --values helm-charts/customer-stack/values-production.yaml \
  --set global.customerName=customer-prod \
  --set global.environment=production \
  --set aws.s3.buckets.documents=customer-prod-docs \
  --set aws.rds.endpoints.litellm=prod-litellm.rds.amazonaws.com
```

### 2. GPU-Enabled Deployment
```bash
helm install customer-gpu helm-charts/customer-stack \
  --namespace customer-gpu-stack \
  --create-namespace \
  --values helm-charts/customer-stack/values-production.yaml \
  --values helm-charts/customer-stack/values-gpu.yaml \
  --set global.customerName=customer-gpu \
  --set ollama.gpu.enabled=true
```

### 3. Development Deployment
```bash
helm install customer-dev helm-charts/customer-stack \
  --namespace customer-dev-stack \
  --create-namespace \
  --set global.customerName=customer-dev \
  --set global.environment=development \
  --set openWebUI.replicaCount=1 \
  --set ollama.persistence.size=50Gi
```

### 4. Custom Values File
```bash
# Create custom values
cat > custom-values.yaml << EOF
global:
  customerName: "enterprise-client"
  environment: "production"

openWebUI:
  replicaCount: 5
  resources:
    requests:
      memory: "2Gi"
      cpu: "1000m"
    limits:
      memory: "8Gi"
      cpu: "4000m"

ollama:
  gpu:
    enabled: true
  models:
    preload:
      - "llama3.1:70b"
      - "codellama:13b"
EOF

# Deploy with custom values
helm install enterprise-client helm-charts/customer-stack \
  --namespace enterprise-client-stack \
  --create-namespace \
  --values custom-values.yaml
```

## 🔐 Security Features

### AWS IAM Integration
- **Service Account**: Automatic IAM role binding for AWS services
- **Least Privilege**: Minimal required permissions
- **Cross-Account Access**: Support for customer AWS accounts

### Network Security
- **Network Policies**: Restrict pod-to-pod communication
- **Security Groups**: AWS-level network controls
- **TLS Encryption**: Secure communication between services

### Data Protection
- **Encryption at Rest**: All persistent volumes encrypted
- **Secrets Management**: Kubernetes secrets for sensitive data
- **Access Controls**: RBAC and pod security contexts

## 📊 Monitoring and Observability

### Health Checks
```yaml
# Liveness and readiness probes configured for all components
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 30

readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 10
```

### Metrics Collection
```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: monitoring
    interval: 30s
```

### Auto-scaling
```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

## 🚨 Troubleshooting

### Common Issues

1. **Pod Startup Issues**
   ```bash
   # Check pod status
   kubectl get pods -n customer-stack
   
   # Check pod logs
   kubectl logs -f deployment/open-webui -n customer-stack
   
   # Describe pod for events
   kubectl describe pod <pod-name> -n customer-stack
   ```

2. **Storage Issues**
   ```bash
   # Check PVC status
   kubectl get pvc -n customer-stack
   
   # Check storage class
   kubectl get storageclass
   
   # Check persistent volumes
   kubectl get pv
   ```

3. **Network Connectivity**
   ```bash
   # Test service connectivity
   kubectl exec -it deployment/open-webui -n customer-stack -- curl http://ollama-service:11434/api/tags
   
   # Check service endpoints
   kubectl get endpoints -n customer-stack
   
   # Check network policies
   kubectl get networkpolicy -n customer-stack
   ```

4. **AWS Integration Issues**
   ```bash
   # Check service account
   kubectl get serviceaccount -n customer-stack
   
   # Check IAM role annotations
   kubectl describe serviceaccount customer-stack-sa -n customer-stack
   
   # Test AWS access
   kubectl exec -it deployment/open-webui -n customer-stack -- aws sts get-caller-identity
   ```

### Debugging Commands
```bash
# Helm debugging
helm template customer-test helm-charts/customer-stack --debug
helm install customer-test helm-charts/customer-stack --dry-run --debug

# Kubernetes debugging
kubectl get events -n customer-stack --sort-by='.lastTimestamp'
kubectl top pods -n customer-stack
kubectl top nodes
```

## 🔄 Upgrade and Rollback

### Upgrade Deployment
```bash
# Upgrade with new values
helm upgrade customer-prod helm-charts/customer-stack \
  --namespace customer-prod-stack \
  --values helm-charts/customer-stack/values-production.yaml \
  --set image.tag=v2.0.0

# Check upgrade status
helm status customer-prod -n customer-prod-stack
```

### Rollback Deployment
```bash
# List release history
helm history customer-prod -n customer-prod-stack

# Rollback to previous version
helm rollback customer-prod -n customer-prod-stack

# Rollback to specific revision
helm rollback customer-prod 2 -n customer-prod-stack
```

## 🧹 Cleanup

### Uninstall Release
```bash
# Uninstall Helm release
helm uninstall customer-prod -n customer-prod-stack

# Delete namespace (optional)
kubectl delete namespace customer-prod-stack

# Clean up persistent volumes (if needed)
kubectl delete pv <pv-name>
```

## 📋 Best Practices

### 1. **Resource Management**
- Set appropriate resource requests and limits
- Use horizontal pod autoscaling for variable workloads
- Monitor resource usage and adjust as needed

### 2. **Storage**
- Use appropriate storage classes (gp3 for general purpose)
- Size persistent volumes based on expected data growth
- Enable backup and snapshot policies

### 3. **Security**
- Always use IAM roles for service accounts
- Enable network policies in production
- Regularly update container images

### 4. **High Availability**
- Deploy across multiple availability zones
- Use pod disruption budgets
- Configure appropriate replica counts

### 5. **Monitoring**
- Enable health checks for all components
- Set up monitoring and alerting
- Use structured logging

---

**Note**: All deployments are AWS-only with no local dependencies. The charts are designed for production use with enterprise-grade security and scalability features.