# White Label AI Assistant - Infrastructure Foundation

This directory contains Terraform modules and configurations for deploying the infrastructure foundation for the white-label AI assistant platform.

## Architecture Overview

The infrastructure follows a modular design with the following components:

- **VPC Module**: Creates isolated VPC with private/public subnet architecture
- **Security Groups Module**: Implements least-privilege security controls
- **EKS Module**: Deploys managed Kubernetes cluster with node groups
- **IAM Module**: Creates necessary roles and policies for service authentication
- **OIDC Provider Module**: Enables IAM roles for service accounts (IRSA)

## Directory Structure

```
terraform/
├── modules/                    # Reusable Terraform modules
│   ├── vpc/                   # VPC and networking resources
│   ├── security-groups/       # Security group definitions
│   ├── eks/                   # EKS cluster and node groups
│   ├── iam/                   # IAM roles and policies
│   └── oidc-provider/         # OIDC identity provider
├── environments/
│   └── customer-template/     # Template for customer deployments
└── README.md                  # This file
```

## Prerequisites

1. **AWS CLI**: Configured with appropriate credentials
2. **Terraform**: Version >= 1.0
3. **kubectl**: For Kubernetes cluster management
4. **AWS IAM Permissions**: The deploying user/role needs permissions to create:
   - VPC and networking resources
   - EKS clusters and node groups
   - IAM roles and policies
   - Security groups
   - CloudWatch log groups

## Quick Start

### 1. Prepare Customer Configuration

```bash
# Navigate to the customer template directory
cd terraform/environments/customer-template

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with customer-specific values
nano terraform.tfvars
```

### 2. Initialize Terraform

```bash
# Initialize Terraform (downloads providers and modules)
terraform init
```

### 3. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 4. Configure kubectl

```bash
# Configure kubectl to connect to the new cluster
aws eks update-kubeconfig --region <aws-region> --name <customer-name>-eks-cluster

# Verify cluster access
kubectl get nodes
```

## Configuration Options

### Basic Configuration

The minimum required variables for deployment:

```hcl
customer_name = "your-customer"
aws_region    = "us-west-2"
environment   = "prod"
```

### Network Configuration

Customize the VPC and subnet configuration:

```hcl
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
```

### EKS Node Groups

Configure the worker node specifications:

```hcl
# General purpose nodes
node_capacity_type   = "ON_DEMAND"  # or "SPOT"
node_instance_types  = ["t3.medium"]
node_desired_size    = 2
node_max_size        = 4
node_min_size        = 1

# GPU nodes for Ollama (optional)
enable_gpu_nodes      = true
gpu_instance_types    = ["g4dn.xlarge"]
gpu_node_desired_size = 1
```

### Security Configuration

Control cluster access:

```hcl
enable_public_access = true
public_access_cidrs  = ["203.0.113.0/24"]  # Restrict to your IP range

enable_node_ssh_access = false  # Enable only if needed for debugging
node_ssh_key_name      = "my-keypair"
```

## Deployment Examples

### Standard Deployment (CPU-only)

For customers who will use external APIs or don't need local GPU inference:

```bash
# Use the standard example
cp terraform.tfvars.example terraform.tfvars
# Edit customer_name and other basic settings
terraform apply
```

### GPU-enabled Deployment

For customers who want to run Ollama with GPU acceleration:

```bash
# Use the GPU example
cp terraform-gpu.tfvars.example terraform.tfvars
# Edit customer_name and other settings
terraform apply
```

## Post-Deployment Steps

After successful deployment, you'll need to:

1. **Install Kubernetes Add-ons**:
   - AWS Load Balancer Controller
   - Cluster Autoscaler (optional)
   - Metrics Server

2. **Configure Storage Classes**:
   - EBS CSI driver is installed automatically
   - Create storage classes for different workload needs

3. **Set up Monitoring**:
   - CloudWatch Container Insights
   - Prometheus/Grafana (optional)

4. **Deploy Applications**:
   - Open WebUI
   - Ollama
   - Qdrant Vector Database

## Outputs

The Terraform configuration provides several useful outputs:

- `cluster_endpoint`: EKS cluster API endpoint
- `cluster_certificate_authority_data`: CA certificate for cluster access
- `kubectl_config_command`: Command to configure kubectl
- Various security group IDs for application deployment
- IAM role ARNs for service accounts

## Security Considerations

### Network Security

- Private subnets for all workloads
- Public subnets only for load balancers
- VPC endpoints for AWS services
- Security groups with least-privilege access

### Access Control

- EKS cluster with private endpoint option
- IAM roles for service accounts (IRSA)
- No direct SSH access to nodes (configurable)

### Data Protection

- Encryption at rest for EBS volumes
- VPC flow logs (can be enabled)
- CloudWatch logging for EKS control plane

## Troubleshooting

### Common Issues

1. **Insufficient IAM Permissions**:
   ```
   Error: AccessDenied: User is not authorized to perform: eks:CreateCluster
   ```
   Solution: Ensure your AWS credentials have the necessary EKS permissions.

2. **Availability Zone Issues**:
   ```
   Error: InvalidParameterException: Subnets specified in an invalid AZ
   ```
   Solution: Update `availability_zones` variable with valid AZs for your region.

3. **Instance Type Not Available**:
   ```
   Error: InvalidParameterValue: Unsupported instance type
   ```
   Solution: Check instance type availability in your chosen AZs.

### Debugging Commands

```bash
# Check Terraform state
terraform show

# Validate configuration
terraform validate

# Check AWS CLI configuration
aws sts get-caller-identity

# Verify EKS cluster status
aws eks describe-cluster --name <cluster-name> --region <region>
```

## Cleanup

To destroy the infrastructure:

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

**Warning**: This will permanently delete all resources. Ensure you have backups of any important data.

## Cost Optimization

### Recommendations

1. **Use Spot Instances**: Set `node_capacity_type = "SPOT"` for non-production workloads
2. **Right-size Instances**: Start with smaller instance types and scale up as needed
3. **Enable Cluster Autoscaler**: Automatically scale nodes based on demand
4. **Monitor Costs**: Use AWS Cost Explorer to track spending

### Estimated Costs (us-west-2)

- **EKS Control Plane**: ~$73/month
- **t3.medium nodes (2x)**: ~$60/month
- **g4dn.xlarge GPU node (1x)**: ~$380/month (if enabled)
- **EBS Storage**: ~$10/month per 100GB
- **Data Transfer**: Variable based on usage

## Support

For issues with this infrastructure configuration:

1. Check the troubleshooting section above
2. Review Terraform and AWS documentation
3. Check AWS service health dashboard
4. Contact your platform administrator

## Next Steps

After deploying the infrastructure foundation:

1. Proceed to Task 2: Customer Stack Core Infrastructure
2. Deploy S3 buckets, Qdrant, and Ollama
3. Configure Open WebUI integration
4. Set up monitoring and logging