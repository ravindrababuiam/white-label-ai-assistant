# Customer Onboarding Automation Scripts

This directory contains automation scripts for deploying the white-label AI assistant to AWS for new customers.

## 🚀 Quick Start

### Deploy a New Customer (Complete Process)
```powershell
# Complete deployment with all steps
./deploy-customer.ps1 -CustomerName "acme-corp" -CustomerEmail "admin@acme.com" -CreateSubaccount -EnableGpu

# Production deployment without subaccount creation
./deploy-customer.ps1 -CustomerName "acme-corp" -CustomerEmail "admin@acme.com" -Environment "production"

# Dry run to validate configuration
./deploy-customer.ps1 -CustomerName "acme-corp" -CustomerEmail "admin@acme.com" -DryRun
```

## 📋 Available Scripts

### 1. `deploy-customer.ps1` - Complete Orchestrator
**Purpose**: Orchestrates the complete customer onboarding process

**Parameters**:
- `CustomerName` (required): Customer identifier (lowercase, alphanumeric, hyphens)
- `CustomerEmail` (required): Customer email for AWS account
- `AwsRegion`: AWS region (default: us-west-2)
- `Environment`: Environment type (development/staging/production)
- `CreateSubaccount`: Create AWS subaccount
- `EnableGpu`: Enable GPU nodes for Ollama
- `DryRun`: Validate without deploying
- `SkipValidation`: Skip parameter validation

**Example**:
```powershell
./deploy-customer.ps1 -CustomerName "customer-xyz" -CustomerEmail "admin@customer-xyz.com" -Environment "production" -EnableGpu
```

### 2. `customer-onboarding.ps1` - Infrastructure Setup
**Purpose**: Creates customer-specific Terraform configuration and deploys infrastructure

**Parameters**:
- `CustomerName` (required): Customer identifier
- `AwsRegion`: AWS region
- `Environment`: Environment type
- `VpcCidr`: VPC CIDR block
- `EnableGpu`: Enable GPU nodes
- `DryRun`: Create configuration without deploying

**Example**:
```powershell
./customer-onboarding.ps1 -CustomerName "customer-abc" -AwsRegion "us-west-2" -EnableGpu
```

### 3. `aws-subaccount-setup.ps1` - AWS Account Management
**Purpose**: Creates and configures AWS subaccounts for customers

**Parameters**:
- `CustomerName` (required): Customer identifier
- `CustomerEmail` (required): Customer email
- `OrganizationId`: AWS Organization ID
- `BillingMode`: Billing access mode
- `DryRun`: Validate without creating

**Example**:
```powershell
./aws-subaccount-setup.ps1 -CustomerName "customer-def" -CustomerEmail "billing@customer-def.com"
```

### 4. `parameter-injection.ps1` - Configuration Management
**Purpose**: Validates and injects customer-specific parameters

**Parameters**:
- `CustomerName` (required): Customer identifier
- `ConfigFile`: Configuration file path
- `Parameters`: Hashtable of parameters
- `ValidateOnly`: Only validate, don't inject
- `Force`: Override validation errors

**Example**:
```powershell
./parameter-injection.ps1 -CustomerName "customer-ghi" -ConfigFile "customers/customer-ghi.conf" -ValidateOnly
```

## 🏗️ Architecture Overview

### AWS Resources Created Per Customer
```
Customer Environment
├── VPC (10.0.0.0/16)
│   ├── Public Subnets (2 AZs)
│   ├── Private Subnets (2 AZs)
│   └── Security Groups
├── EKS Cluster
│   ├── Managed Node Groups
│   ├── GPU Nodes (optional)
│   └── Applications
│       ├── Open WebUI
│       ├── Ollama
│       └── Qdrant
├── RDS PostgreSQL
│   ├── LiteLLM Database
│   └── Lago Database
├── ElastiCache Redis
│   ├── LiteLLM Cache
│   └── Lago Cache
└── S3 Buckets
    ├── Document Storage
    └── Application Data
```

### Deployment Flow
```
1. AWS Subaccount Setup (optional)
   ↓
2. Parameter Validation & Injection
   ↓
3. Terraform Configuration Generation
   ↓
4. Infrastructure Deployment
   ↓
5. Kubernetes Configuration
   ↓
6. Application Deployment
   ↓
7. Validation & Testing
   ↓
8. Access Information & Documentation
```

## 📁 Directory Structure

```
scripts/
├── deploy-customer.ps1          # Main orchestrator
├── customer-onboarding.ps1      # Infrastructure setup
├── aws-subaccount-setup.ps1     # AWS account management
├── parameter-injection.ps1      # Configuration validation
└── README.md                    # This file

customers/
├── {customer-name}.conf         # Customer configuration
├── {customer-name}-setup-instructions.md
└── {customer-name}-deployment-report.md

terraform/environments/
└── {customer-name}/
    ├── main.tf                  # Terraform configuration
    ├── variables.tf             # Variable definitions
    ├── terraform.tfvars         # Customer values
    ├── backend.tf               # State configuration
    ├── deploy.sh                # Deployment script
    ├── validate.sh              # Validation script
    └── README.md                # Customer documentation
```

## ⚙️ Configuration

### Customer Configuration File Format
```ini
[Customer]
Name = "customer-name"
Email = "admin@customer.com"
Environment = "production"

[AWS]
Region = "us-west-2"
AccountId = "123456789012"

[Infrastructure]
VpcCidr = "10.0.0.0/16"
EnableGpu = false
NodeInstanceTypes = ["t3.medium"]

[Security]
EncryptionEnabled = true
BackupEnabled = true
```

### Parameter Schema
The scripts validate parameters against a comprehensive schema including:
- **Required fields**: customer_name, aws_region, environment, vpc_cidr
- **Type validation**: string, integer, boolean, array
- **Pattern matching**: CIDR blocks, naming conventions
- **Range validation**: Node counts, retention periods
- **Business logic**: GPU costs, sizing recommendations

## 🔐 Security Features

### Infrastructure Security
- ✅ All databases in private subnets
- ✅ Encryption at rest and in transit
- ✅ Security groups with least-privilege access
- ✅ IAM roles with minimal permissions
- ✅ VPC endpoints for AWS services

### Access Control
- ✅ Cross-account roles for management
- ✅ External ID for additional security
- ✅ Audit logging enabled
- ✅ Resource tagging for compliance

## 🔍 Validation and Testing

### Automated Validation
- Parameter schema validation
- AWS resource availability checks
- Terraform configuration validation
- Kubernetes deployment verification
- Application health checks

### Manual Testing
```powershell
# Test deployment with dry run
./deploy-customer.ps1 -CustomerName "test-customer" -CustomerEmail "test@example.com" -DryRun

# Validate existing deployment
cd terraform/environments/test-customer
./validate.sh

# Check application access
kubectl get services -n customer-stack
```

## 🚨 Troubleshooting

### Common Issues

1. **AWS Credentials**
   ```powershell
   aws sts get-caller-identity  # Verify credentials
   aws configure list           # Check configuration
   ```

2. **Terraform State**
   ```powershell
   terraform init               # Reinitialize if needed
   terraform refresh            # Sync state
   ```

3. **Kubernetes Access**
   ```powershell
   aws eks update-kubeconfig --region us-west-2 --name customer-eks-cluster
   kubectl config current-context
   ```

4. **Parameter Validation**
   ```powershell
   ./parameter-injection.ps1 -CustomerName "customer" -ValidateOnly
   ```

### Log Locations
- **Terraform logs**: `terraform/environments/{customer}/`
- **Deployment reports**: `customers/{customer}-deployment-report.md`
- **Parameter summaries**: `terraform/environments/{customer}/parameter-summary.md`

## 📊 Monitoring and Maintenance

### Health Checks
```powershell
# Quick health check
kubectl get pods -n customer-stack
aws rds describe-db-instances --region us-west-2
aws elasticache describe-replication-groups --region us-west-2
```

### Cost Optimization
- Use appropriate instance sizes for environment
- Enable S3 lifecycle policies
- Configure auto-scaling for EKS nodes
- Monitor and optimize GPU usage

### Backup and Recovery
- RDS automated backups (7 days retention)
- S3 versioning enabled
- EBS snapshots for persistent volumes
- Terraform state backup

## 🎯 Best Practices

1. **Always run dry-run first** for new customers
2. **Validate parameters** before deployment
3. **Use consistent naming** conventions
4. **Tag all resources** appropriately
5. **Monitor costs** and usage
6. **Keep documentation** updated
7. **Test disaster recovery** procedures

---

**Note**: All scripts ensure everything runs in AWS only - no local dependencies or services.