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

variable "advertise_public_hostname" {
  type        = bool
  default     = false
  description = "When true, Hydra public URLs use https://public_hostname instead of run.app"
}

variable "admin_hostname" {
  type        = string
  default     = "oauth2-w.stawi.org"
  description = "Canonical Hydra admin host (DNS via edge-lb-identity). IAM-authenticated, not anonymous-public."
}

variable "advertise_admin_hostname" {
  type        = bool
  default     = false
  description = "When true, Hydra admin base URL uses https://admin_hostname instead of run.app"
}

variable "admin_exposure" {
  type        = string
  default     = "authenticated"
  description = "Hydra admin service exposure: authenticated (default) or private. Never public."
  validation {
    condition     = contains(["authenticated", "private"], var.admin_exposure)
    error_message = "admin_exposure must be authenticated or private."
  }
}

variable "additional_admin_invoker_members" {
  type        = set(string)
  default     = []
  description = "Extra run.invoker members for Hydra admin (cross-project runtime SAs)"
}

# ---------------------------------------------------------------------------
# Supabase migration (docs/superpowers/specs/2026-08-31-supabase-migration-design.md)
# ---------------------------------------------------------------------------
variable "supabase_access_token" {
  type        = string
  sensitive   = true
  default     = "unused"
  description = "Supabase org access token (from SOPS credentials via CI — never commit)"
}

variable "supabase_org_id" {
  type        = string
  default     = ""
  description = "Supabase organization slug (from supabase-accounts registry / SOPS)"
}

variable "supabase_region" {
  type    = string
  default = "eu-central-1"
}

variable "supabase_enabled" {
  type        = bool
  default     = false
  description = "Phase 1: create the Supabase project + staging secrets (no service impact)"
}

variable "database_cutover" {
  type        = bool
  default     = false
  description = "Phase 2: point the live DB secrets at Supabase (requires supabase_enabled and completed data copy)"
}
