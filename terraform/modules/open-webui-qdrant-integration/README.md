# Open WebUI Qdrant Integration Module

This Terraform module provides comprehensive Qdrant vector database integration for Open WebUI, enabling document indexing, vector search, and RAG (Retrieval Augmented Generation) capabilities.

## Features

- **Document Processing**: Automatic text extraction from various document formats (PDF, DOCX, XLSX, PPTX, HTML, TXT)
- **Vector Embeddings**: Support for multiple embedding providers (OpenAI, Hugging Face, Ollama, local models)
- **Vector Search**: High-performance similarity search with Qdrant
- **Hybrid Search**: Combines vector similarity and text-based search
- **RAG Support**: Retrieval Augmented Generation for enhanced AI responses
- **Auto-scaling**: Kubernetes HPA for dynamic scaling based on load
- **Monitoring**: Prometheus metrics and health checks
- **Security**: Network policies, RBAC, and secure secret management

## Architecture

The module deploys four main services:

1. **Embedding Service** (Port 8001): Generates vector embeddings for text
2. **Vector Search Service** (Port 8002): Performs similarity search in Qdrant
3. **Document Indexer Service** (Port 8003): Processes and indexes documents
4. **Search API Service** (Port 8004): Unified API for Open WebUI integration

## Usage

```hcl
module "qdrant_integration" {
  source = "./modules/open-webui-qdrant-integration"

  # Basic Configuration
  customer_name = "example-customer"
  namespace     = "open-webui"
  
  # Qdrant Configuration
  qdrant_url         = "http://qdrant:6333"
  qdrant_api_key     = var.qdrant_api_key
  collection_name    = "documents"
  vector_size        = 1536
  distance_metric    = "Cosine"
  
  # Embedding Configuration
  embedding_provider = "openai"
  embedding_model    = "text-embedding-ada-002"
  openai_api_key     = var.openai_api_key
  
  # S3 Configuration for Document Storage
  s3_endpoint = "https://s3.amazonaws.com"
  s3_bucket   = "customer-documents"
  
  # Search Configuration
  enable_hybrid_search = true
  enable_reranking     = false
  auto_index_documents = true
  
  # RAG Configuration
  enable_rag         = true
  rag_context_window = 4000
  rag_max_chunks     = 5
  
  # Scaling Configuration
  enable_embedding_hpa = true
  enable_search_hpa    = true
  
  # Resource Configuration
  embedding_service_resources = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2"
      memory = "4Gi"
    }
  }
  
  common_labels = {
    "environment" = "production"
    "team"        = "ai-platform"
  }
}
```

## Configuration Variables

### Core Configuration

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `customer_name` | Customer identifier for resource naming | `string` | Required |
| `namespace` | Kubernetes namespace | `string` | `"open-webui"` |
| `qdrant_url` | Qdrant server URL | `string` | Required |
| `collection_name` | Qdrant collection name | `string` | `"documents"` |

### Embedding Configuration

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `embedding_provider` | Provider (openai, huggingface, local, ollama) | `string` | `"openai"` |
| `embedding_model` | Model name | `string` | `"text-embedding-ada-002"` |
| `vector_size` | Embedding vector size | `number` | `1536` |
| `normalize_embeddings` | Normalize vectors to unit length | `bool` | `true` |

### Search Configuration

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `enable_hybrid_search` | Enable hybrid vector+text search | `bool` | `true` |
| `enable_reranking` | Enable result reranking | `bool` | `false` |
| `default_search_limit` | Default number of results | `number` | `10` |
| `score_threshold` | Minimum similarity threshold | `number` | `0.7` |

### Document Processing

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `auto_index_documents` | Auto-index uploaded documents | `bool` | `true` |
| `text_chunk_size` | Text chunk size for embedding | `number` | `1000` |
| `text_chunk_overlap` | Overlap between chunks | `number` | `200` |
| `extract_keywords` | Extract keywords for hybrid search | `bool` | `true` |

## Outputs

| Output | Description |
|--------|-------------|
| `embedding_service_endpoint` | Embedding service API endpoint |
| `search_service_endpoint` | Vector search service endpoint |
| `indexer_service_endpoint` | Document indexer service endpoint |
| `search_api_endpoint` | Unified search API endpoint |
| `integration_status` | Overall integration status and configuration |

## API Endpoints

### Embedding Service (Port 8001)
- `POST /embeddings` - Generate single embedding
- `POST /embeddings/batch` - Generate batch embeddings
- `GET /health` - Health check
- `GET /metrics` - Prometheus metrics

### Vector Search Service (Port 8002)
- `POST /search` - Search documents
- `POST /search/vector` - Vector similarity search
- `GET /collection/info` - Collection information
- `GET /health` - Health check

### Document Indexer Service (Port 8003)
- `POST /index` - Index a document
- `GET /status/{document_id}` - Get indexing status
- `DELETE /documents/{document_id}` - Delete document
- `GET /jobs` - List indexing jobs

### Search API Service (Port 8004)
- `POST /search` - Unified search interface
- `POST /rag/context` - Get RAG context
- `POST /rag/prompt` - Generate RAG prompt
- `GET /suggestions` - Query suggestions
- `GET /api/v1/documents/search` - Open WebUI compatible endpoint

## Supported Document Formats

- **Text**: Plain text, HTML, XML
- **PDF**: Portable Document Format
- **Microsoft Office**: DOCX, XLSX, PPTX
- **Legacy Office**: DOC, XLS, PPT (with additional libraries)

## Monitoring and Observability

### Health Checks
All services provide health and readiness endpoints for Kubernetes probes.

### Metrics
Prometheus metrics are exposed on `/metrics` endpoints:
- Request counts and latencies
- Embedding generation metrics
- Search performance metrics
- Document processing statistics
- Cache hit rates

### Logging
Structured logging with configurable levels:
- Request/response logging
- Error tracking
- Performance monitoring
- Debug information

## Security Features

### Network Security
- Kubernetes Network Policies for traffic isolation
- Service-to-service communication restrictions
- Ingress controls for external access

### Authentication & Authorization
- Kubernetes RBAC for service accounts
- API key management for external services
- Secure secret storage

### Data Protection
- Encryption in transit (TLS)
- Secure credential handling
- Input validation and sanitization

## Scaling and Performance

### Auto-scaling
- Horizontal Pod Autoscaler (HPA) support
- CPU and memory-based scaling
- Custom metrics scaling (optional)

### Resource Management
- Configurable resource requests and limits
- Node selector and toleration support
- Efficient resource utilization

### Caching
- Embedding caching for performance
- Configurable cache TTL and size limits
- Memory-efficient cache management

## Troubleshooting

### Common Issues

1. **Qdrant Connection Failed**
   - Check Qdrant URL and API key
   - Verify network connectivity
   - Check Qdrant service status

2. **Embedding Generation Errors**
   - Verify API keys for embedding providers
   - Check rate limits and quotas
   - Monitor service logs for errors

3. **Document Processing Failures**
   - Check supported document formats
   - Verify S3 access permissions
   - Monitor indexing job status

4. **Search Performance Issues**
   - Review search parameters and thresholds
   - Check Qdrant collection status
   - Monitor resource utilization

### Debugging Commands

```bash
# Check pod status
kubectl get pods -n open-webui -l customer=example-customer

# View service logs
kubectl logs -n open-webui deployment/example-customer-embedding-service

# Check service health
kubectl exec -n open-webui deployment/example-customer-search-api-service -- curl localhost:8004/health

# Monitor metrics
kubectl port-forward -n open-webui svc/example-customer-search-api-service 8004:8004
curl http://localhost:8004/metrics
```

## Development

### Building Custom Images

```dockerfile
# Use the provided Dockerfile as base
FROM python:3.11-slim
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY *.py ./
CMD ["python", "-m", "uvicorn", "embedding_service:app", "--host", "0.0.0.0", "--port", "8001"]
```

### Testing

```bash
# Install dependencies
pip install -r requirements.txt

# Run tests
pytest tests/

# Run individual services
python embedding_service.py
python vector_search.py
python document_indexer.py
python search_api.py
```

## Contributing

1. Follow Python PEP 8 style guidelines
2. Add comprehensive tests for new features
3. Update documentation for configuration changes
4. Ensure security best practices are followed

## License

This module is part of the white-label AI assistant platform and follows the project's licensing terms.