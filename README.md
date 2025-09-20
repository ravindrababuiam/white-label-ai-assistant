# White-Label AI Assistant Platform

A production-ready white-label intranet AI assistant platform for businesses with GDPR compliance and usage-based billing.

## 🎯 Overview

This platform provides businesses with a dual-mode AI assistant:
- **Local Mode**: GDPR-compliant processing using Ollama in customer's AWS subaccount
- **External Mode**: API routing through LiteLLM to external providers (OpenAI, Anthropic, etc.)

## 🏗️ Architecture

### Per-Customer Stack (Isolated)
- **VPC**: 3-AZ design with private/public subnets
- **EKS Cluster**: Managed Kubernetes with auto-scaling
- **Open WebUI**: User interface and document management
- **Ollama**: Local AI model processing
- **Qdrant**: Vector database for embeddings
- **S3**: Encrypted document storage with customer-managed KMS keys

### Central Stack (Shared)
- **LiteLLM Proxy**: Multi-tenant API routing and usage tracking
- **Lago**: Self-hosted billing system with €/1k token pricing
- **MCP Server**: Task execution and external tool integration

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured
- GitHub CLI installed
- Terraform >= 1.0
- Helm >= 3.12
- kubectl

### Deploy via CI/CD

1. **Trigger Customer Deployment**:
   ```bash
   gh workflow run customer-deployment.yml \
     -f customer_name=your-customer \
     -f environment=development \
     -f aws_region=us-west-2 \
     -f enable_gpu=false \
     -f deployment_type=full-deployment
   ```

2. **Monitor Deployment**:
   - Check GitHub Actions for progress
   - Download deployment report artifact
   - Verify resources in AWS console

## 📁 Repository Structure

```
├── .github/workflows/     # CI/CD pipelines
├── .kiro/specs/          # Project specifications
├── terraform/            # Infrastructure as Code
│   ├── modules/          # Reusable Terraform modules
│   └── environments/     # Customer-specific configurations
├── helm-charts/          # Kubernetes application deployments
├── scripts/              # Automation scripts
├── gitops/              # ArgoCD configurations
└── central-services/    # LiteLLM and Lago deployments
```

## 🔐 Security & Compliance

- **GDPR Compliant**: Customer data never leaves their AWS subaccount
- **Encryption**: Customer-managed KMS keys for all data
- **Network Isolation**: Private subnets with VPC endpoints
- **Audit Logging**: Complete audit trails for compliance
- **Data Deletion**: Automated DSAR compliance procedures

## 📊 Billing & Usage

- **Usage-Based**: €/1k tokens consumed
- **Multi-Tenant**: Lago dashboard for customer billing visibility
- **Real-Time Tracking**: LiteLLM usage events to Lago
- **Transparent**: Customers access their own billing dashboard

## 🔧 MCP Integration

- **Task Execution**: Connect to external tools and APIs
- **Secure Communication**: mTLS/JWT authentication
- **Privacy-First**: Only metadata shared, no PII
- **Extensible**: Easy addition of new MCP servers

## 📚 Documentation

- [Requirements](/.kiro/specs/white-label-ai-assistant/requirements.md)
- [Design](/.kiro/specs/white-label-ai-assistant/design.md)
- [Implementation Tasks](/.kiro/specs/white-label-ai-assistant/tasks.md)
- [Scripts Documentation](/scripts/README.md)
- [Helm Charts Documentation](/helm-charts/README.md)
- [GitOps Documentation](/gitops/README.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with CI/CD pipeline
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For support and questions:
- Create an issue in this repository
- Check the documentation in `.kiro/specs/`
- Review CI/CD logs in GitHub Actions