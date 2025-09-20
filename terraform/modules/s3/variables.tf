variable "customer_name" {
  description = "Name of the customer"
  type        = string
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "encryption_algorithm" {
  description = "Server-side encryption algorithm"
  type        = string
  default     = "AES256"
}

variable "enable_lifecycle" {
  description = "Enable S3 lifecycle configuration"
  type        = bool
  default     = true
}

variable "transition_to_ia_days" {
  description = "Days after which objects transition to Standard-IA"
  type        = number
  default     = 30
}

variable "transition_to_glacier_days" {
  description = "Days after which objects transition to Glacier"
  type        = number
  default     = 90
}

variable "expiration_days" {
  description = "Days after which objects expire"
  type        = number
  default     = 365
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which noncurrent versions expire"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}