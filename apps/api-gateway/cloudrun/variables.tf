variable "app_name" { type = string }
variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "europe-west1"
}
variable "platform" { type = string }
variable "labels" {
  type    = map(string)
  default = {}
}
# CI may still export these; unused for LB-only stack.
variable "neon_api_key" {
  type      = string
  sensitive = true
  default   = "unused"
}
variable "neon_org_id" {
  type    = string
  default = ""
}
variable "neon_region_id" {
  type    = string
  default = "aws-eu-central-1"
}
variable "image" {
  type        = string
  default     = "unused"
  description = "Unused — gateway stack has no container image"
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token (Zone:DNS:Edit on stawi.org)"
}

variable "cloudflare_zone_id" {
  type        = string
  default     = "706bf604a333d866bb38c03bf643e79a"
  description = "Cloudflare zone id for stawi.org"
}

variable "cloudflare_proxied" {
  type        = bool
  default     = false
  description = "CF orange-cloud on traffic A (false until cert ACTIVE)"
}

variable "identity_project_id" {
  type        = string
  default     = "stawi-identity"
  description = "GCP project for identity Cloud Run backends"
}

variable "platform_project_id" {
  type        = string
  default     = "stawi-platform"
  description = "GCP project for platform Cloud Run backends"
}

variable "operations_project_id" {
  type        = string
  default     = "stawi-operations"
  description = "GCP project for operations Cloud Run backends"
}

variable "hostname" {
  type        = string
  default     = "api.stawi.org"
  description = "Public unified API hostname"
}
