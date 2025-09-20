# IAM Module Variables

variable "customer_name" {
  description = "Name of the customer for resource naming"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for EKS cluster"
  type        = string
  default     = ""
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL for EKS cluster"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}