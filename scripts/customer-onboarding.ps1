# Customer Onboarding Automation Script
# This script automates the creation of customer infrastructure using Terraform

param(
    [Parameter(Mandatory=$true)]
    [string]$CustomerName,
    
    [Parameter(Mandatory=$true)]
    [string]$CustomerEmail,
    
    [Parameter(Mandatory=$false)]
    [string]$AwsRegion = "us-west-2",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "production",
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableGpu = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateSubaccount = $false
)

# Set error handling
$ErrorActionPreference = "Stop"

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TerraformDir = Join-Path (Split-Path -Parent $ScriptDir) "terraform"
$CustomerDir = Join-Path $TerraformDir "environments" $CustomerName

Write-Host "🚀 Starting customer onboarding for: $CustomerName" -ForegroundColor Green
Write-Host "📧 Customer Email: $CustomerEmail" -ForegroundColor Cyan
Write-Host "🌍 AWS Region: $AwsRegion" -ForegroundColor Cyan
Write-Host "🏗️ Environment: $Environment" -ForegroundColor Cyan

# Step 1: Validate prerequisites
Write-Host "`n📋 Step 1: Validating prerequisites..." -ForegroundColor Yellow

# Check if Terraform is installed
try {
    $terraformVersion = terraform version
    Write-Host "✅ Terraform found: $($terraformVersion[0])" -ForegroundColor Green
} catch {
    Write-Error "❌ Terraform not found. Please install Terraform first."
    exit 1
}

# Check if AWS CLI is installed and configured
try {
    $awsIdentity = aws sts get-caller-identity --output json | ConvertFrom-Json
    Write-Host "✅ AWS CLI configured for account: $($awsIdentity.Account)" -ForegroundColor Green
} catch {
    Write-Error "❌ AWS CLI not configured. Please run 'aws configure' first."
    exit 1
}

# Step 2: Create customer directory structure
Write-Host "`n📁 Step 2: Creating customer directory structure..." -ForegroundColor Yellow

if (Test-Path $CustomerDir) {
    Write-Warning "⚠️ Customer directory already exists: $CustomerDir"
    $overwrite = Read-Host "Do you want to overwrite? (y/N)"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") {
        Write-Host "❌ Aborted by user" -ForegroundColor Red
        exit 1
    }
    Remove-Item $CustomerDir -Recurse -Force
}

New-Item -ItemType Directory -Path $CustomerDir -Force | Out-Null
Write-Host "✅ Created customer directory: $CustomerDir" -ForegroundColor Green

# Step 3: Generate customer-specific Terraform configuration
Write-Host "`n⚙️ Step 3: Generating Terraform configuration..." -ForegroundColor Yellow

# Create main.tf
$mainTf = @"
# Customer: $CustomerName
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
  
  backend "s3" {
    bucket = "my-terra-bucket-001"
    key    = "customers/$CustomerName/terraform.tfstate"
    region = "$AwsRegion"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Customer    = var.customer_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "white-label-ai-assistant"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Local values
locals {
  customer_name = var.customer_name
  environment   = var.environment
  aws_region    = var.aws_region
  
  common_tags = {
    Customer    = local.customer_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Project     = "white-label-ai-assistant"
  }
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"
  
  customer_name = local.customer_name
  environment   = local.environment
  aws_region    = local.aws_region
  
  vpc_cidr = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)
  
  tags = local.common_tags
}

# IAM Module
module "iam" {
  source = "../../modules/iam"
  
  customer_name = local.customer_name
  
  common_tags = local.common_tags
}

# Security Groups Module
module "security_groups" {
  source = "../../modules/security-groups"
  
  customer_name = local.customer_name
  vpc_id        = module.vpc.vpc_id
  
  common_tags = local.common_tags
}

# EKS Module
module "eks" {
  source = "../../modules/eks"
  
  customer_name                    = local.customer_name
  private_subnet_ids              = module.vpc.private_subnet_ids
  public_subnet_ids               = module.vpc.public_subnet_ids
  control_plane_security_group_id = module.security_groups.eks_control_plane_security_group_id
  worker_nodes_security_group_id  = module.security_groups.eks_worker_nodes_security_group_id
  cluster_service_role_arn        = module.iam.eks_cluster_service_role_arn
  node_group_role_arn            = module.iam.eks_node_group_role_arn
  
  enable_gpu_nodes = var.enable_gpu
  
  common_tags = local.common_tags
}

# S3 Module
module "s3" {
  source = "../../modules/s3"
  
  customer_name = local.customer_name
  
  tags = local.common_tags
}

# RDS Module (for application data)
module "rds" {
  source = "../../modules/rds"
  
  customer_name      = local.customer_name
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.rds_security_group_id]
  
  tags = local.common_tags
}
"@

$mainTf | Out-File -FilePath (Join-Path $CustomerDir "main.tf") -Encoding UTF8
Write-Host "✅ Generated main.tf" -ForegroundColor Green

# Create variables.tf
$variablesTf = @"
# Customer-specific variables for $CustomerName

variable "customer_name" {
  description = "Name of the customer"
  type        = string
  default     = "$CustomerName"
}

variable "customer_email" {
  description = "Customer contact email"
  type        = string
  default     = "$CustomerEmail"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "$AwsRegion"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "$Environment"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_gpu" {
  description = "Enable GPU support for AI workloads"
  type        = bool
  default     = $($EnableGpu.ToString().ToLower())
}

variable "node_groups" {
  description = "EKS node group configurations"
  type = map(object({
    instance_types = list(string)
    scaling_config = object({
      desired_size = number
      max_size     = number
      min_size     = number
    })
    capacity_type = string
  }))
  default = {
    general = {
      instance_types = ["t3.medium", "t3.large"]
      scaling_config = {
        desired_size = 2
        max_size     = 10
        min_size     = 1
      }
      capacity_type = "ON_DEMAND"
    }
$(if ($EnableGpu) {
@"
    gpu = {
      instance_types = ["g4dn.xlarge", "g4dn.2xlarge"]
      scaling_config = {
        desired_size = 1
        max_size     = 3
        min_size     = 0
      }
      capacity_type = "ON_DEMAND"
    }
"@
})
  }
}
"@

$variablesTf | Out-File -FilePath (Join-Path $CustomerDir "variables.tf") -Encoding UTF8
Write-Host "✅ Generated variables.tf" -ForegroundColor Green

# Create outputs.tf
$outputsTf = @"
# Outputs for customer $CustomerName

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "eks_cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for document storage"
  value       = module.s3.bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = module.s3.bucket_arn
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
  sensitive   = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.rds.db_instance_port
}

output "customer_info" {
  description = "Customer information"
  value = {
    name         = var.customer_name
    email        = var.customer_email
    environment  = var.environment
    region       = var.aws_region
    gpu_enabled  = var.enable_gpu
  }
}
"@

$outputsTf | Out-File -FilePath (Join-Path $CustomerDir "outputs.tf") -Encoding UTF8
Write-Host "✅ Generated outputs.tf" -ForegroundColor Green

# Step 4: Initialize Terraform
Write-Host "`n🔧 Step 4: Initializing Terraform..." -ForegroundColor Yellow

Push-Location $CustomerDir
try {
    terraform init
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform init failed"
    }
    Write-Host "✅ Terraform initialized successfully" -ForegroundColor Green
} catch {
    Write-Error "❌ Failed to initialize Terraform: $_"
    Pop-Location
    exit 1
}

# Step 5: Plan deployment
Write-Host "`n📋 Step 5: Creating deployment plan..." -ForegroundColor Yellow

try {
    terraform plan -out="$CustomerName.tfplan"
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform plan failed"
    }
    Write-Host "✅ Terraform plan created successfully" -ForegroundColor Green
} catch {
    Write-Error "❌ Failed to create Terraform plan: $_"
    Pop-Location
    exit 1
}

Pop-Location

# Step 6: Summary and next steps
Write-Host "`n🎉 Customer onboarding preparation completed!" -ForegroundColor Green
Write-Host "📁 Customer directory: $CustomerDir" -ForegroundColor Cyan
Write-Host "📋 Terraform plan: $CustomerName.tfplan" -ForegroundColor Cyan

Write-Host "`n📝 Next steps:" -ForegroundColor Yellow
Write-Host "1. Review the Terraform plan in: $CustomerDir" -ForegroundColor White
Write-Host "2. Apply the infrastructure:" -ForegroundColor White
Write-Host "   cd `"$CustomerDir`"" -ForegroundColor Gray
Write-Host "   terraform apply `"$CustomerName.tfplan`"" -ForegroundColor Gray
Write-Host "3. Deploy applications using Helm charts" -ForegroundColor White

if ($CreateSubaccount) {
    Write-Host "`n⚠️ Note: AWS subaccount creation was requested but not implemented in this script." -ForegroundColor Yellow
    Write-Host "Please create the subaccount manually or use AWS Organizations API." -ForegroundColor Yellow
}

Write-Host "`n✅ Customer onboarding automation completed successfully!" -ForegroundColor Green