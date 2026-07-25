variable "app_name" {
  type        = string
  description = "Application name (directory name; Cloud Run service name)"
}

variable "image" {
  type        = string
  description = "Caddy container image"
  default     = "caddy:2.8-alpine"
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west9"
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "platform" {
  type = string
}

# CI still exports these when loading credentials; unused (no Neon).
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

variable "public_hostname" {
  type        = string
  default     = "api.stawi.org"
  description = "Custom domain for this edge (requires domain verification + mapping)"
}

variable "enable_domain_mapping" {
  type        = bool
  default     = false
  description = "Create Cloud Run domain mapping (requires gcloud domains verify stawi.org)"
}

variable "region_run" {
  type        = string
  default     = "europe-west9"
  description = "Region used in backend run.app hostnames"
}

variable "identity_project_number" {
  type    = string
  default = "721554040672"
}

variable "platform_project_number" {
  type    = string
  default = "305282281906"
}
