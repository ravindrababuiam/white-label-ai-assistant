# Open WebUI S3 Integration Module

This Terraform module implements comprehensive S3 document storage integration for Open WebUI, including secure file upload handling, virus scanning, metadata extraction, and document indexing functionality.

## Features

- **Secure File Upload**: Multi-layered validation with content type checking and filename sanitization
- **Virus Scanning**: Integration with multiple antivirus engines (ClamAV, API-based, Windows Defender)
- **Metadata Extraction**: Comprehensive metadata extraction from various file types (PDF, DOCX, Excel, images, audio)
- **Document Processing**: Automated text extraction, OCR, and thumbnail generation
- **Vector Indexing**: Integration with Qdrant for document search and retrieval
- **Chunked Uploads**: Support for large file uploads with progress tracking
- **Quarantine System**: Automatic quarantine of suspicious files with management interface
- **IRSA Support**: IAM Roles for Service Accounts for secure AWS access
- **Auto-scaling**: Horizontal Pod Autoscaler for processing workloads

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                S3 Integration Architecture                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │   Open WebUI    │    │  Upload Handler │    │ Document        │ │
│  │                 │    │                 │    │ Processor       │ │
│  │ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │ │
│  │ │File Upload  │ │───▶│ │Chunk Upload │ │───▶│ │Virus Scanner│ │ │
│  │ │Interface    │ │    │ │Progress     │ │    │ │Metadata Ext.│ │ │
│  │ └─────────────┘ │    │ │Tracking     │ │    │ │S3 Upload    │ │ │
│  └─────────────────┘    │ └─────────────┘ │    │ └─────────────┘ │ │
│                         └─────────────────┘    └─────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
          │                      │                      │
          │ File Validation      │ Processing Pipeline  │ Storage & Indexing
          ▼                      ▼                      ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Security      │    │   Processing    │    │   Storage       │
│   - Virus Scan  │    │   - Text Extract│    │   - S3 Bucket   │
│   - Content Val │    │   - Metadata    │    │   - Qdrant DB   │
│   - Quarantine  │    │   - Thumbnails  │    │   - Encryption  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Usage

### Basic S3 Integration

```hcl
module "s3_integration" {
  source = "./modules/open-webui-s3-integration"

  customer_name   = "acme-corp"
  namespace      = "open-webui"
  s3_bucket_name = "acme-corp-documents"
  s3_region      = "us-east-1"
  
  # Security configuration
  enable_virus_scanning = true
  enable_content_type_validation = true
  enable_filename_sanitization = true
  
  # Processing configuration
  enable_metadata_indexing = true
  extract_text_content = true
  generate_thumbnails = true
  
  # Qdrant integration
  qdrant_url = "http://acme-corp-qdrant.qdrant.svc.cluster.local:6333"
  qdrant_api_key = var.qdrant_api_key
  
  # AWS credentials
  aws_access_key_id = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
  
  common_labels = {
    Environment = "production"
    Project     = "ai-assistant"
  }
}
```

### Production Deployment with IRSA

```hcl
module "s3_integration_prod" {
  source = "./modules/open-webui-s3-integration"

  customer_name   = "acme-corp"
  namespace      = "open-webui"
  s3_bucket_name = "acme-corp-documents"
  s3_region      = "us-east-1"
  
  # Enable IRSA for secure AWS access
  enable_irsa = true
  eks_cluster_name = "acme-corp-cluster"
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  
  # Enhanced security
  enable_virus_scanning = true
  quarantine_suspicious_files = true
  virus_scan_api_key = var.virus_scan_api_key
  
  # Advanced processing
  enable_metadata_indexing = true
  extract_text_content = true
  generate_thumbnails = true
  enable_ocr = true
  
  # File upload limits
  max_file_size = 104857600  # 100MB
  allowed_file_extensions = [
    ".pdf", ".docx", ".txt", ".md", ".csv",
    ".jpg", ".png", ".gif", ".mp3", ".mp4"
  ]
  
  # Processing resources
  processor_replicas = 3
  processor_resources = {
    requests = {
      cpu    = "1"
      memory = "2Gi"
    }
    limits = {
      cpu    = "4"
      memory = "8Gi"
    }
  }
  
  # Auto-scaling
  enable_processor_hpa = true
  processor_hpa_min_replicas = 2
  processor_hpa_max_replicas = 10
  
  # Qdrant integration
  qdrant_url = "http://acme-corp-qdrant.qdrant.svc.cluster.local:6333"
  qdrant_api_key = var.qdrant_api_key
  
  # Network security
  enable_network_policy = true
  
  common_labels = {
    Environment = "production"
    Project     = "ai-assistant"
    Customer    = "acme-corp"
  }
}
```

### Development Configuration

```hcl
module "s3_integration_dev" {
  source = "./modules/open-webui-s3-integration"

  customer_name   = "dev-environment"
  namespace      = "open-webui-dev"
  s3_bucket_name = "dev-documents"
  s3_region      = "us-east-1"
  
  # Simplified security for development
  enable_virus_scanning = false
  enable_content_type_validation = false
  quarantine_suspicious_files = false
  
  # Basic processing
  enable_metadata_indexing = true
  extract_text_content = true
  generate_thumbnails = false
  enable_ocr = false
  
  # Minimal resources
  processor_replicas = 1
  processor_resources = {
    requests = {
      cpu    = "200m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "1"
      memory = "2Gi"
    }
  }
  
  # Disable auto-scaling
  enable_processor_hpa = false
  enable_network_policy = false
  
  # AWS credentials (use IAM user for dev)
  enable_irsa = false
  aws_access_key_id = var.dev_aws_access_key_id
  aws_secret_access_key = var.dev_aws_secret_access_key
  
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
| aws | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| kubernetes | ~> 2.23 |
| aws | ~> 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| customer_name | Name of the customer | `string` | n/a | yes |
| namespace | Kubernetes namespace | `string` | `"open-webui"` | no |
| s3_bucket_name | S3 bucket name | `string` | n/a | yes |
| s3_region | S3 bucket region | `string` | `"us-east-1"` | no |
| enable_virus_scanning | Enable virus scanning | `bool` | `true` | no |
| enable_metadata_indexing | Enable metadata indexing | `bool` | `true` | no |
| max_file_size | Maximum file size in bytes | `number` | `104857600` | no |
| processor_replicas | Number of processor replicas | `number` | `2` | no |

## Outputs

| Name | Description |
|------|-------------|
| document_processor_endpoint | Document processor API endpoint |
| s3_bucket_name | S3 bucket name used |
| service_account_name | Service account name (if IRSA enabled) |
| iam_role_arn | IAM role ARN (if IRSA enabled) |
| integration_status | Integration configuration status |

## File Processing Pipeline

### 1. Upload Validation
- File size limits
- Extension whitelist
- Content type validation
- Filename sanitization

### 2. Virus Scanning
- **ClamAV**: Open-source antivirus engine
- **API-based**: External virus scanning services
- **Windows Defender**: Native Windows protection
- **Quarantine**: Automatic isolation of threats

### 3. Metadata Extraction

#### Supported File Types
- **PDF**: Text content, document properties, page count
- **Microsoft Office**: DOCX, XLSX, PPTX with full metadata
- **Images**: EXIF data, dimensions, OCR text extraction
- **Audio**: ID3 tags, duration, bitrate information
- **Text Files**: Content extraction with encoding detection

#### Extracted Metadata
```json
{
  "file_info": {
    "filename": "document.pdf",
    "file_size": 1048576,
    "mime_type": "application/pdf",
    "file_hash": "sha256:abc123...",
    "created_time": "2024-01-01T00:00:00Z"
  },
  "content_metadata": {
    "text_content": "Extracted text content...",
    "document_info": {
      "title": "Document Title",
      "author": "Author Name",
      "page_count": 10
    }
  },
  "content_stats": {
    "character_count": 5000,
    "word_count": 800,
    "line_count": 100
  }
}
```

### 4. S3 Storage
- Encrypted storage with customer-managed keys
- Organized folder structure by user and date
- Metadata tags for searchability
- Lifecycle policies for cost optimization

### 5. Vector Indexing
- Text content embedding generation
- Storage in Qdrant vector database
- Metadata indexing for hybrid search
- Real-time search capabilities

## Security Features

### Virus Scanning
```hcl
enable_virus_scanning = true
quarantine_suspicious_files = true
virus_scan_timeout = 60
```

### Content Validation
```hcl
enable_content_type_validation = true
enable_filename_sanitization = true
allowed_file_extensions = [".pdf", ".docx", ".txt"]
```

### Access Control
```hcl
enable_irsa = true
kms_key_arn = "arn:aws:kms:region:account:key/key-id"
enable_network_policy = true
```

## API Endpoints

The document processor service exposes the following endpoints:

### Upload Document
```http
POST /upload
Content-Type: multipart/form-data

file: [binary file data]
user_id: string
document_type: string
```

### Health Check
```http
GET /health
```

### Document Information
```http
GET /document/{document_id}
```

### Quarantine Management
```http
GET /quarantine
POST /quarantine/{file_hash}/release
```

### Processing Statistics
```http
GET /stats
```

## Monitoring & Observability

### Health Checks
- Service availability monitoring
- Virus scanner status
- S3 connectivity checks
- Qdrant integration status

### Metrics
- Upload success/failure rates
- Processing times
- Virus detection statistics
- Storage utilization

### Logging
- Structured JSON logging
- Processing pipeline tracking
- Security event logging
- Performance metrics

## Troubleshooting

### Common Issues

1. **Upload failures**
   ```bash
   # Check processor logs
   kubectl logs -n open-webui deployment/customer-document-processor
   
   # Check S3 connectivity
   kubectl exec -n open-webui deployment/customer-document-processor -- python -c "
   from scripts.s3_client import S3DocumentClient
   client = S3DocumentClient()
   print(client.health_check())
   "
   ```

2. **Virus scanning issues**
   ```bash
   # Check scanner status
   kubectl exec -n open-webui deployment/customer-document-processor -- python -c "
   from scripts.virus_scanner import VirusScanner
   scanner = VirusScanner()
   print(scanner.health_check())
   "
   ```

3. **Metadata extraction problems**
   ```bash
   # Check extraction capabilities
   kubectl exec -n open-webui deployment/customer-document-processor -- python -c "
   from scripts.metadata_extractor import MetadataExtractor
   extractor = MetadataExtractor()
   print(extractor.health_check())
   "
   ```

### Useful Commands

```bash
# Port forward to processor service
kubectl port-forward -n open-webui svc/customer-document-processor 8000:8000

# View processor logs
kubectl logs -n open-webui deployment/customer-document-processor -f

# Check HPA status
kubectl get hpa -n open-webui

# Scale processor manually
kubectl scale -n open-webui deployment/customer-document-processor --replicas=5

# Check quarantined files
curl http://localhost:8000/quarantine

# Get processing statistics
curl http://localhost:8000/stats
```

## Integration with Open WebUI

### JavaScript Integration
```javascript
// Upload file with progress tracking
async function uploadDocument(file, userId) {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('user_id', userId);
    
    const response = await fetch('/api/documents/upload', {
        method: 'POST',
        body: formData
    });
    
    return await response.json();
}
```

### Python Integration
```python
import requests

def upload_document(file_path, user_id, processor_url):
    with open(file_path, 'rb') as f:
        files = {'file': f}
        data = {'user_id': user_id}
        
        response = requests.post(
            f"{processor_url}/upload",
            files=files,
            data=data
        )
    
    return response.json()
```

This module provides a complete, production-ready S3 integration solution for Open WebUI with comprehensive security, processing, and monitoring capabilities.