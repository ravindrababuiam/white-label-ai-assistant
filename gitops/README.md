# GitOps and CI/CD Pipeline

This directory contains GitOps configurations and CI/CD pipeline definitions for the white-label AI assistant deployment automation.

## 🚀 Overview

The GitOps workflow provides:
- **Automated deployments** triggered by code changes
- **Infrastructure as Code** with Terraform
- **Application deployments** with Helm and ArgoCD
- **Rollback procedures** for quick recovery
- **Disaster recovery** automation
- **Multi-environment** support

## 📁 Directory Structure

```
.github/workflows/
├── infrastructure-update.yml     # Infrastructure CI/CD pipeline
├── customer-deployment.yml       # Customer deployment workflow
├── disaster-recovery.yml         # Disaster recovery procedures
└── rollback.yml                  # Rollback automation

gitops/
├── argocd/
│   ├── application-template.yaml # ArgoCD application template
│   └── appproject.yaml          # ArgoCD project configuration
├── applications/                # Generated ArgoCD applications
├── sync-reports/                # Sync operation reports
├── generate-argocd-app.ps1      # ArgoCD application generator
├── sync-argocd-apps.ps1         # ArgoCD sync manager
└── README.md                    # This file
```

## 🔄 CI/CD Workflows

### 1. Infrastructure Update Pipeline
**Trigger**: Push to main/develop branches with changes to `terraform/`, `helm-charts/`, or `scripts/`

**Stages**:
1. **Change Detection** - Identifies affected customers and components
2. **Validation** - Terraform format, validation, and planning
3. **Security Scan** - Vulnerability scanning and secret detection
4. **Approval Gate** - Manual approval for production changes
5. **Deployment** - Automated infrastructure and application updates
6. **Validation** - Post-deployment health checks
7. **Rollback** - Automatic rollback on failure

**Usage**:
```bash
# Triggered automatically on push to main
git push origin main

# Or manually trigger via GitHub Actions UI
```

### 2. Customer Deployment Workflow
**Trigger**: Manual workflow dispatch

**Parameters**:
- Customer name
- Environment (development/staging/production)
- AWS region
- GPU support
- Deployment type
- Subaccount creation

**Usage**:
```bash
# Via GitHub CLI
gh workflow run customer-deployment.yml \
  -f customer_name=acme-corp \
  -f environment=production \
  -f aws_region=us-west-2 \
  -f enable_gpu=true

# Or via GitHub Actions UI
```

### 3. Disaster Recovery Workflow
**Trigger**: Manual workflow dispatch

**Recovery Types**:
- **Backup Restore** - Restore from RDS/EBS snapshots
- **Full Rebuild** - Complete infrastructure recreation
- **Cross-Region Failover** - Failover to different AWS region

**Usage**:
```bash
# Backup restore
gh workflow run disaster-recovery.yml \
  -f customer_name=customer-xyz \
  -f recovery_type=backup-restore \
  -f backup_timestamp=2025-09-19-14-30

# Full rebuild
gh workflow run disaster-recovery.yml \
  -f customer_name=customer-xyz \
  -f recovery_type=full-rebuild

# Cross-region failover
gh workflow run disaster-recovery.yml \
  -f customer_name=customer-xyz \
  -f recovery_type=cross-region-failover \
  -f source_region=us-west-2 \
  -f target_region=us-east-1
```

### 4. Rollback Workflow
**Trigger**: Manual workflow dispatch

**Rollback Types**:
- **Application Only** - Helm rollback to previous revision
- **Infrastructure Only** - Terraform rollback to previous state
- **Full Rollback** - Both application and infrastructure rollback

**Usage**:
```bash
# Application rollback
gh workflow run rollback.yml \
  -f customer_name=customer-abc \
  -f rollback_type=application-only

# Full rollback to specific revision
gh workflow run rollback.yml \
  -f customer_name=customer-abc \
  -f rollback_type=full-rollback \
  -f target_revision=v1.2.3
```

## 🎯 ArgoCD GitOps

### Application Generation
Generate ArgoCD applications for customers:

```powershell
# Generate ArgoCD application
./gitops/generate-argocd-app.ps1 -CustomerName "acme-corp" -Environment "production"

# Generate with GPU support
./gitops/generate-argocd-app.ps1 -CustomerName "ai-startup" -EnableGpu

# Dry run validation
./gitops/generate-argocd-app.ps1 -CustomerName "test-customer" -DryRun
```

### Application Synchronization
Manage ArgoCD application sync:

```powershell
# Sync all applications
./gitops/sync-argocd-apps.ps1 -SyncAll

# Sync specific customer
./gitops/sync-argocd-apps.ps1 -CustomerName "acme-corp"

# Sync specific environment
./gitops/sync-argocd-apps.ps1 -Environment "production"

# Force sync with pruning
./gitops/sync-argocd-apps.ps1 -CustomerName "customer-xyz" -Force -Prune
```

### ArgoCD Project Configuration
The `appproject.yaml` defines:
- **Source repositories** allowed for deployments
- **Destination clusters** and namespaces
- **Resource whitelists** for security
- **RBAC roles** for team access
- **Sync windows** for controlled deployments

## 🔐 Security and Compliance

### Approval Gates
- **Production deployments** require manual approval
- **Rollback operations** require approval
- **Disaster recovery** requires approval

### Security Scanning
- **Vulnerability scanning** with Trivy
- **Secret detection** with TruffleHog
- **Code analysis** with PSScriptAnalyzer and ShellCheck
- **Helm security** validation

### Access Control
- **GitHub environments** for approval workflows
- **ArgoCD RBAC** for GitOps access
- **AWS IAM roles** for service authentication

## 📊 Monitoring and Observability

### Pipeline Monitoring
- **Workflow status** tracking
- **Deployment reports** generation
- **Failure notifications**
- **Rollback tracking**

### Application Monitoring
- **ArgoCD application health** monitoring
- **Kubernetes resource** status
- **AWS service** health checks
- **Custom metrics** collection

## 🛠️ Configuration

### GitHub Secrets
Required secrets for CI/CD workflows:

```bash
# AWS credentials
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_ACCOUNT_ID

# ArgoCD credentials (if using external ArgoCD)
ARGOCD_SERVER
ARGOCD_TOKEN

# Notification credentials (optional)
SLACK_WEBHOOK_URL
TEAMS_WEBHOOK_URL
```

### Environment Variables
Configure in workflow files:

```yaml
env:
  TERRAFORM_VERSION: '1.5.0'
  HELM_VERSION: '3.12.0'
  KUBECTL_VERSION: 'v1.28.0'
  ARGOCD_VERSION: 'v2.8.0'
```

### ArgoCD Configuration
Update `argocd/appproject.yaml` with:
- Your Git repository URLs
- Your ArgoCD server URL
- Your team/group names for RBAC
- Your sync window preferences

## 🚀 Getting Started

### 1. Setup Prerequisites
```bash
# Install required tools
# - GitHub CLI
# - AWS CLI
# - kubectl
# - Helm
# - ArgoCD CLI (optional)

# Configure AWS credentials
aws configure

# Configure kubectl for EKS
aws eks update-kubeconfig --region us-west-2 --name your-cluster
```

### 2. Configure GitHub Repository
```bash
# Set up GitHub secrets
gh secret set AWS_ACCESS_KEY_ID --body "your-access-key"
gh secret set AWS_SECRET_ACCESS_KEY --body "your-secret-key"
gh secret set AWS_ACCOUNT_ID --body "your-account-id"

# Enable GitHub Actions
# - Go to repository Settings > Actions > General
# - Enable "Allow all actions and reusable workflows"
```

### 3. Deploy ArgoCD (if not already deployed)
```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Apply project configuration
kubectl apply -f gitops/argocd/appproject.yaml
```

### 4. Deploy First Customer
```bash
# Use the customer deployment workflow
gh workflow run customer-deployment.yml \
  -f customer_name=first-customer \
  -f environment=production \
  -f deployment_type=full-deployment
```

## 📋 Best Practices

### 1. **Branch Strategy**
- Use `main` branch for production deployments
- Use `develop` branch for staging deployments
- Create feature branches for development

### 2. **Environment Management**
- Separate AWS accounts for production
- Use different regions for disaster recovery
- Implement proper resource tagging

### 3. **Security**
- Rotate AWS credentials regularly
- Use IAM roles instead of access keys when possible
- Enable MFA for critical operations
- Regular security scanning

### 4. **Monitoring**
- Set up CloudWatch alarms
- Monitor ArgoCD application health
- Track deployment metrics
- Set up alerting for failures

### 5. **Backup and Recovery**
- Regular RDS snapshots
- EBS volume snapshots
- Cross-region backup replication
- Test disaster recovery procedures

## 🔧 Troubleshooting

### Common Issues

1. **Workflow Failures**
   ```bash
   # Check workflow logs
   gh run list --workflow=infrastructure-update.yml
   gh run view <run-id>
   ```

2. **ArgoCD Sync Issues**
   ```bash
   # Check application status
   argocd app get customer-stack-name
   
   # Force sync
   argocd app sync customer-stack-name --force
   ```

3. **Terraform State Issues**
   ```bash
   # Refresh state
   terraform refresh
   
   # Import existing resources
   terraform import aws_instance.example i-1234567890abcdef0
   ```

4. **Kubernetes Issues**
   ```bash
   # Check pod status
   kubectl get pods -n customer-stack
   
   # Check events
   kubectl get events -n customer-stack --sort-by='.lastTimestamp'
   ```

### Support Contacts
- **Platform Team**: platform@yourcompany.com
- **DevOps Team**: devops@yourcompany.com
- **On-call**: Use your incident management system

---

**Note**: All deployments are AWS-only with comprehensive GitOps automation for reliable, scalable operations.