variable "app_name" {
  type        = string
  description = "Application name (Cloud Run service, Neon project, secret id prefix)"
}

variable "image" {
  type        = string
  description = "Container image for Cloud Run"
}

variable "neon_region_id" {
  type        = string
  default     = "aws-eu-central-1"
  description = "Neon region id"
}

variable "neon_api_key" {
  type        = string
  sensitive   = true
  description = "Neon API key; set via TF_VAR_neon_api_key or -var in CI"
}

variable "platform" {
  type        = string
  description = "Platform module to load: stawi-dev | stawi-prod"
  validation {
    condition     = contains(["stawi-dev", "stawi-prod"], var.platform)
    error_message = "platform must be stawi-dev or stawi-prod"
  }
}
