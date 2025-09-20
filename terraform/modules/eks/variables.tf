# EKS Module Variables

variable "customer_name" {
  description = "Name of the customer for resource naming"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS cluster"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for EKS cluster"
  type        = list(string)
}

variable "control_plane_security_group_id" {
  description = "Security group ID for EKS control plane"
  type        = string
}

variable "worker_nodes_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  type        = string
}

variable "cluster_service_role_arn" {
  description = "ARN of the IAM role for EKS cluster service"
  type        = string
}

variable "node_group_role_arn" {
  description = "ARN of the IAM role for EKS node group"
  type        = string
}

variable "enable_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "List of CIDR blocks that can access the public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "log_retention_days" {
  description = "Number of days to retain EKS cluster logs"
  type        = number
  default     = 7
}

# Node Group Configuration
variable "node_capacity_type" {
  description = "Type of capacity associated with the EKS Node Group. Valid values: ON_DEMAND, SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_instance_types" {
  description = "List of instance types for EKS node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes in the EKS node group"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes in the EKS node group"
  type        = number
  default     = 4
}

variable "node_min_size" {
  description = "Minimum number of nodes in the EKS node group"
  type        = number
  default     = 1
}

variable "node_disk_size" {
  description = "Disk size in GiB for worker nodes"
  type        = number
  default     = 50
}

variable "node_ami_type" {
  description = "Type of Amazon Machine Image (AMI) associated with the EKS Node Group"
  type        = string
  default     = "AL2_x86_64"
}

# GPU Node Group Configuration
variable "enable_gpu_nodes" {
  description = "Enable GPU node group for Ollama workloads"
  type        = bool
  default     = false
}

variable "gpu_instance_types" {
  description = "List of GPU instance types for Ollama workloads"
  type        = list(string)
  default     = ["g4dn.xlarge"]
}

variable "gpu_node_desired_size" {
  description = "Desired number of GPU nodes"
  type        = number
  default     = 1
}

variable "gpu_node_max_size" {
  description = "Maximum number of GPU nodes"
  type        = number
  default     = 2
}

variable "gpu_node_min_size" {
  description = "Minimum number of GPU nodes"
  type        = number
  default     = 0
}

variable "gpu_node_disk_size" {
  description = "Disk size in GiB for GPU worker nodes"
  type        = number
  default     = 100
}

# SSH Access Configuration
variable "enable_node_ssh_access" {
  description = "Enable SSH access to worker nodes"
  type        = bool
  default     = false
}

variable "node_ssh_key_name" {
  description = "EC2 Key Pair name for SSH access to worker nodes"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}