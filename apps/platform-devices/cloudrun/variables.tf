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

variable "extra_secret_values" {
  type        = map(string)
  sensitive   = true
  default     = {}
  description = "Additional SM secrets (id → value) managed by tofu"
}

variable "extra_secret_ids" {
  type        = set(string)
  default     = []
  description = "SM secret IDs to create without versions"
}

variable "identity_project_id" {
  type        = string
  default     = "stawi-identity"
  description = "Identity GCP project hosting Hydra/Keto for OIDC and authz"
}

variable "identity_region" {
  type        = string
  default     = "europe-west1"
  description = "Region of identity Cloud Run services"
}

variable "public_hostname" {
  type        = string
  default     = ""
  description = "Canonical public FQDN for this service (Cloud Run domain mapping)"
}

# TURN / WebRTC (colony service-devices.yaml). Empty = omit Cloudflare secrets.
variable "cloudflare_turn_token_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cloudflare_turn_api_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "turn_server_urls" {
  type        = string
  default     = "turn:turn.example.com:3478,turns:turn.example.com:5349,stun:stun.example.com:3478"
  description = "Comma-separated TURN/STUN URLs (cluster placeholder until production TURN)"
}

variable "turn_shared_secret" {
  type        = string
  sensitive   = true
  default     = "setmecorrectly"
  description = "TURN shared secret; prefer real value via TF_VAR / CI secret"
}

