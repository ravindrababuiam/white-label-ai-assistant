# Test Configuration for Infrastructure Foundation
# Customer: test-deployment

# Customer Configuration
customer_name = "test-deployment"
environment   = "dev"
aws_region    = "us-west-2"

# Network Configuration
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-west-2a", "us-west-2b"]

# EKS Configuration
kubernetes_version    = "1.28"
enable_public_access  = true
public_access_cidrs   = ["0.0.0.0/0"]  # For testing - restrict in production
log_retention_days    = 7

# Node Group Configuration (upgraded for better memory)
node_capacity_type   = "ON_DEMAND"
node_instance_types  = ["t3.medium"]  # Better memory (4GB) for AI workloads
node_desired_size    = 3
node_max_size        = 5
node_min_size        = 2
node_disk_size       = 50

# GPU Node Configuration (disabled for initial test)
enable_gpu_nodes      = false
gpu_instance_types    = ["g4dn.xlarge"]
gpu_node_desired_size = 0
gpu_node_max_size     = 1
gpu_node_min_size     = 0
gpu_node_disk_size    = 100

# SSH Access (disabled for security)
enable_node_ssh_access = false
node_ssh_key_name      = ""