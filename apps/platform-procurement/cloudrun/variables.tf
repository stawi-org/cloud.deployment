variable "app_name" {
  type        = string
  description = "Application name (directory name; Cloud Run service + Neon project prefix)"
}

variable "image" {
  type        = string
  description = "Container image for Cloud Run"
}

variable "project_id" {
  type        = string
  description = "GCP project from gcp-accounts registry (resolved by CI)"
}

variable "region" {
  type        = string
  description = "GCP region from gcp-accounts registry"
  default     = "europe-west1"
}

variable "labels" {
  type        = map(string)
  description = "Resource labels from gcp-accounts registry"
  default     = {}
}

variable "platform" {
  type        = string
  description = "Deploy env name (stawi-dev | stawi-prod) for edge-contract"
}

variable "neon_region_id" {
  type    = string
  default = "aws-eu-central-1"
}

variable "neon_org_id" {
  type        = string
  description = "Neon organization id (from neon-accounts registry / SOPS)"
  default     = ""
}

variable "neon_api_key" {
  type        = string
  sensitive   = true
  description = "Neon org API key (from SOPS credentials via CI — never commit)"
}

variable "identity_project_id" {
  type        = string
  default     = "stawi-identity"
  description = "Identity GCP project (Hydra/Keto). Identity-domain apps: set null in main."
}

variable "identity_region" {
  type        = string
  default     = "europe-west1"
  description = "Region of identity Cloud Run services"
}

variable "resource_path" {
  type        = string
  default     = ""
  description = "OAuth resource path under api base (empty → derived from app_name)"
}

variable "requested_audience_paths" {
  type        = list(string)
  default     = ["/profile", "/tenancy"]
  description = "Extra OAuth audience paths under api base"
}

variable "neon_extensions" {
  type        = list(string)
  default     = []
  description = "Empty → base suite (uuid-ossp, pg_stat_statements, pg_trgm, btree_gin, btree_gist)"
}

variable "has_database" {
  type    = bool
  default = true
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "migrate_args" {
  type    = list(string)
  default = ["setup"]
}
