# Main Terraform Configuration for Customer Infrastructure
# This template can be used to deploy infrastructure for each customer

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Backend configuration should be customized per customer
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "customers/${var.customer_name}/terraform.tfstate"
  #   region = "us-west-2"
  # }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Local values
locals {
  common_tags = {
    Environment   = var.environment
    Customer      = var.customer_name
    Project       = "white-label-ai-assistant"
    ManagedBy     = "terraform"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
  }

  # Calculate subnet CIDRs based on VPC CIDR
  vpc_cidr_parts = split("/", var.vpc_cidr)
  vpc_cidr_base  = local.vpc_cidr_parts[0]
  vpc_cidr_mask  = tonumber(local.vpc_cidr_parts[1])
  
  # Create subnet CIDRs (assuming /24 subnets in a /16 VPC)
  public_subnet_cidrs = [
    for i in range(length(var.availability_zones)) :
    cidrsubnet(var.vpc_cidr, 8, i)
  ]
  
  private_subnet_cidrs = [
    for i in range(length(var.availability_zones)) :
    cidrsubnet(var.vpc_cidr, 8, i + 10)
  ]
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  customer_name           = var.customer_name
  aws_region             = var.aws_region
  vpc_cidr               = var.vpc_cidr
  availability_zones     = var.availability_zones
  public_subnet_cidrs    = local.public_subnet_cidrs
  private_subnet_cidrs   = local.private_subnet_cidrs
  common_tags           = local.common_tags
}

# Security Groups Module
module "security_groups" {
  source = "../../modules/security-groups"

  customer_name = var.customer_name
  vpc_id        = module.vpc.vpc_id
  common_tags   = local.common_tags
}

# IAM Module (initial roles)
module "iam_initial" {
  source = "../../modules/iam"

  customer_name = var.customer_name
  common_tags   = local.common_tags
}

# EKS Cluster Module
module "eks" {
  source = "../../modules/eks"

  customer_name                    = var.customer_name
  kubernetes_version              = var.kubernetes_version
  private_subnet_ids              = module.vpc.private_subnet_ids
  public_subnet_ids               = module.vpc.public_subnet_ids
  control_plane_security_group_id = module.security_groups.eks_control_plane_security_group_id
  worker_nodes_security_group_id  = module.security_groups.eks_worker_nodes_security_group_id
  cluster_service_role_arn        = module.iam_initial.eks_cluster_service_role_arn
  node_group_role_arn            = module.iam_initial.eks_node_group_role_arn
  
  # Node group configuration
  node_capacity_type    = var.node_capacity_type
  node_instance_types   = var.node_instance_types
  node_desired_size     = var.node_desired_size
  node_max_size         = var.node_max_size
  node_min_size         = var.node_min_size
  node_disk_size        = var.node_disk_size
  
  # GPU node configuration
  enable_gpu_nodes      = var.enable_gpu_nodes
  gpu_instance_types    = var.gpu_instance_types
  gpu_node_desired_size = var.gpu_node_desired_size
  gpu_node_max_size     = var.gpu_node_max_size
  gpu_node_min_size     = var.gpu_node_min_size
  gpu_node_disk_size    = var.gpu_node_disk_size
  
  # Access configuration
  enable_public_access    = var.enable_public_access
  public_access_cidrs     = var.public_access_cidrs
  enable_node_ssh_access  = var.enable_node_ssh_access
  node_ssh_key_name       = var.node_ssh_key_name
  
  log_retention_days = var.log_retention_days
  common_tags       = local.common_tags

  depends_on = [
    module.vpc,
    module.security_groups,
    module.iam_initial
  ]
}

# OIDC Provider Module
module "oidc_provider" {
  source = "../../modules/oidc-provider"

  customer_name    = var.customer_name
  oidc_issuer_url  = module.eks.cluster_oidc_issuer_url
  common_tags      = local.common_tags

  depends_on = [module.eks]
}

# Note: Service account IAM roles will be created separately when needed
# The basic IAM roles for EKS cluster and node groups are already created in iam_initial module