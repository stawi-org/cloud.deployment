variable "project_id" {
  type        = string
  description = "GCP project where secrets are stored (usually the app's runtime project)"
}

variable "secret_ids" {
  type        = set(string)
  description = "Secret IDs to create (non-sensitive keys only — required for for_each)"
  default     = []
}

variable "version_ids" {
  type        = set(string)
  description = "Subset of secret_ids that get a tofu-managed version (must be non-sensitive literals/sets — never keys() of a sensitive map)"
  default     = []
}

variable "secret_values" {
  type        = map(string)
  description = "Map of secret_id → payload for version_ids managed in tofu"
  sensitive   = true
  default     = {}
}

variable "accessor_members" {
  type        = list(string)
  description = "IAM members granted roles/secretmanager.secretAccessor"
  default     = []
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "replication_user_managed_locations" {
  type        = list(string)
  description = "If non-empty, user-managed replication to these regions; else automatic"
  default     = []
}
