# OIDC Provider Module Variables

variable "customer_name" {
  description = "Name of the customer for resource naming"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL from EKS cluster"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}