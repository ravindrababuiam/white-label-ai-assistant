# Variables for Customer S3 Module

variable "customer_name" {
  description = "Name of the customer (used for resource naming)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.customer_name))
    error_message = "Customer name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "vpc_id" {
  description = "VPC ID where the customer infrastructure is deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for VPC endpoint"
  type        = list(string)
}

variable "kms_deletion_window" {
  description = "Number of days to wait before deleting KMS key"
  type        = number
  default     = 7
  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for disaster recovery"
  type        = bool
  default     = false
}

variable "replication_destination_bucket" {
  description = "Destination bucket ARN for cross-region replication"
  type        = string
  default     = ""
}

variable "replication_destination_region" {
  description = "Destination region for cross-region replication"
  type        = string
  default     = ""
}

variable "lifecycle_transition_ia_days" {
  description = "Number of days before transitioning to Standard-IA"
  type        = number
  default     = 30
}

variable "lifecycle_transition_glacier_days" {
  description = "Number of days before transitioning to Glacier"
  type        = number
  default     = 90
}

variable "lifecycle_transition_deep_archive_days" {
  description = "Number of days before transitioning to Deep Archive"
  type        = number
  default     = 365
}

variable "allowed_service_principals" {
  description = "List of AWS service principals allowed to access the bucket"
  type        = list(string)
  default     = ["ec2.amazonaws.com", "ecs-tasks.amazonaws.com", "eks.amazonaws.com"]
}