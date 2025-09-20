# Customer Template Outputs

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

# EKS Outputs
output "cluster_id" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_id
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = module.eks.cluster_version
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

# Security Group Outputs
output "eks_control_plane_security_group_id" {
  description = "Security group ID for EKS control plane"
  value       = module.security_groups.eks_control_plane_security_group_id
}

output "eks_worker_nodes_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  value       = module.security_groups.eks_worker_nodes_security_group_id
}

output "alb_security_group_id" {
  description = "Security group ID for Application Load Balancer"
  value       = module.security_groups.alb_security_group_id
}

output "open_webui_security_group_id" {
  description = "Security group ID for Open WebUI"
  value       = module.security_groups.open_webui_security_group_id
}

output "ollama_security_group_id" {
  description = "Security group ID for Ollama"
  value       = module.security_groups.ollama_security_group_id
}

output "qdrant_security_group_id" {
  description = "Security group ID for Qdrant"
  value       = module.security_groups.qdrant_security_group_id
}

# IAM Outputs
output "eks_cluster_service_role_arn" {
  description = "ARN of the EKS cluster service role"
  value       = module.iam_initial.eks_cluster_service_role_arn
}

output "eks_node_group_role_arn" {
  description = "ARN of the EKS node group role"
  value       = module.iam_initial.eks_node_group_role_arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller role"
  value       = module.iam_initial.aws_load_balancer_controller_role_arn
}

output "ebs_csi_driver_role_arn" {
  description = "ARN of the EBS CSI Driver role"
  value       = module.iam_initial.ebs_csi_driver_role_arn
}

# OIDC Provider Outputs
output "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = module.oidc_provider.oidc_provider_arn
}

# Kubectl Configuration Command
output "kubectl_config_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_id}"
}