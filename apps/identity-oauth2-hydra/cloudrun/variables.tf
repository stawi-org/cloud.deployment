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
  description = "Neon organization id (from neon-accounts registry / SOPS); required for project create"
  default     = ""
}

variable "neon_api_key" {
  type        = string
  sensitive   = true
  description = "Neon org API key (from SOPS credentials via CI (SOPS_AGE_KEY) — never commit)"
}

variable "extra_secret_values" {
  type        = map(string)
  sensitive   = true
  default     = {}
  description = "Additional SM secrets (id → value) managed by tofu; prefer empty and out-of-band for human secrets"
}

variable "extra_secret_ids" {
  type        = set(string)
  default     = []
  description = "SM secret IDs to create without versions (fill versions outside git)"
}

variable "public_hostname" {
  type        = string
  default     = "oauth2.stawi.org"
  description = "Canonical public host (K8s parity). Used when advertise_public_hostname=true."
}

variable "enable_domain_mapping" {
  type        = bool
  default     = false
  description = "Create Cloud Run domain mapping for public_hostname (needs domain verification)"
}

variable "advertise_public_hostname" {
  type        = bool
  default     = false
  description = "When true, Hydra URLs/issuer endpoints use https://public_hostname instead of run.app"
}
