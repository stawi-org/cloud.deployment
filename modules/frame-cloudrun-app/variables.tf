# Canonical Frame Cloud Run application stack.
# Used by identity/ops/platform Frame services (not Hydra/Keto/edge-lb).

variable "app_name" {
  type        = string
  description = "Cloud Run service name / Neon project prefix (directory name)"
}

variable "oauth2_service_client_id" {
  type        = string
  default     = ""
  description = "Hydra OAuth2 client_id for private_key_jwt (colony SA id, e.g. service-profile). Empty derives service-* from app_name."
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west9"
}

variable "platform" {
  type        = string
  description = "stawi-dev | stawi-prod (edge-contract + public hosts)"
}

variable "image" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

# ---------------------------------------------------------------------------
# Identity discovery (Hydra / Keto). Null project → same as project_id.
# ---------------------------------------------------------------------------

variable "identity_project_id" {
  type        = string
  default     = null
  description = "GCP project hosting Hydra/Keto; null = this project (identity domain)"
}

variable "identity_region" {
  type        = string
  default     = null
  description = "Region of identity Cloud Run services; null = var.region"
}

variable "use_hydra_admin_service" {
  type        = bool
  default     = true
  description = "Read identity-oauth2-hydra-admin for OAUTH2_SERVICE_ADMIN_URI (IAM-protected). Set false before admin service exists."
}

variable "enable_keto" {
  type        = bool
  default     = true
  description = "Look up keto-read/write and wire AUTHORIZATION_SERVICE_* to CR URIs"
}

variable "enable_keto_admin" {
  type        = bool
  default     = true
  description = "Set KETO_SERVICE_ADMIN_URI to keto-write (tuple writers)"
}

variable "oauth_signer_secret" {
  type        = string
  default     = "hydra-webhook-psk"
  description = "SM secret id for OAUTH2_SIGNER_API_KEY; empty = omit signer secret"
}

variable "grant_oauth_signer_accessor" {
  type        = bool
  default     = true
  description = "Grant runtime SA secretAccessor on oauth_signer_secret (when not module-owned)"
}

# ---------------------------------------------------------------------------
# Database (Neon)
# ---------------------------------------------------------------------------

variable "has_database" {
  type    = bool
  default = true
}

variable "neon_org_id" {
  type    = string
  default = ""
}

variable "neon_region_id" {
  type    = string
  default = "aws-eu-central-1"
}

variable "neon_extensions" {
  type        = list(string)
  default     = []
  description = "Empty → neon-database module defaults (or none when has_database=false)"
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

variable "extra_secret_ids" {
  type        = set(string)
  default     = []
  description = "Additional SM secret ids (created; versions only if in extra_secret_values)"
}

variable "extra_secret_values" {
  type        = map(string)
  sensitive   = true
  default     = {}
  description = "SM id → value for tofu-managed secret versions"
}

variable "extra_version_ids" {
  type        = set(string)
  default     = []
  description = "Non-sensitive set of extra_secret_ids that get tofu-managed versions. Must have matching entries in extra_secret_values. Leave empty when values are seeded out-of-band (Vault/k8s → SM)."
}

variable "secret_env_extra" {
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default     = {}
  description = "Extra secret env on the Cloud Run service (merged after DB + signer)"
}

variable "migrate_secret_env_extra" {
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------

variable "container_port" {
  type    = number
  default = 8080
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "use_http2" {
  type        = bool
  default     = true
  description = "h2c for Connect/gRPC-friendly Frame services"
}

variable "public_invoker" {
  type        = bool
  default     = null
  description = "Override allUsers invoker. Null → derived from exposure (public only)."
}

variable "exposure" {
  type        = string
  default     = "public"
  description = "public | authenticated | private — see modules/cloudrun-service and docs/SERVICE_EXPOSURE.md"

  validation {
    condition     = contains(["public", "authenticated", "private"], var.exposure)
    error_message = "exposure must be public, authenticated, or private."
  }
}

variable "invoker_members" {
  type        = set(string)
  default     = []
  description = "IAM members granted roles/run.invoker when exposure is authenticated/private"
}

variable "custom_audiences" {
  type        = list(string)
  default     = []
  description = "Extra OIDC audiences for Cloud Run (e.g. https://tenancy.stawi.org) when callers mint tokens for the edge DNS hostname"
}

variable "min_instance_count" {
  type        = number
  default     = 0
  description = "Use 1 only for in-process schedulers (e.g. trustage mem:// wakes)"
}

variable "max_instance_count" {
  type    = number
  default = 5
}

variable "startup_probe_path" {
  type    = string
  default = ""
}

variable "liveness_probe_path" {
  type    = string
  default = ""
}

variable "disable_otel_exporters" {
  type        = bool
  default     = true
  description = "Set OTEL_*_EXPORTER=none on the service (until real collectors exist)"
}

variable "resource_path" {
  type        = string
  default     = ""
  description = "OAuth resource path under api base (e.g. /devices). Empty → /{app without domain- prefix}"
}

variable "requested_audience_paths" {
  type        = list(string)
  default     = ["/profile", "/tenancy"]
  description = "Outbound OAuth audience paths under api base (business deps). Own resource_path is not included — see OAUTH2_RESOURCE_AUDIENCE. /tenancy is auto-appended when permissions_registration is true."
}

variable "app_env" {
  type        = map(string)
  default     = {}
  description = "App-specific env (wins over frame defaults)"
}

variable "service_env_extra" {
  type        = map(string)
  default     = {}
  description = "Merged after messaging, before app_env (e.g. trustage queue URLs)"
}

# ---------------------------------------------------------------------------
# Migrate job
# ---------------------------------------------------------------------------

variable "migrate_execute" {
  type        = bool
  default     = false
  description = "Run migrate on apply (prefer false; CI or manual job)"
}

variable "migrate_args" {
  type        = list(string)
  # Frame setup plan: argv "setup" with no task list runs every registered step
  # (migrate, bootstrap, permissions, verify, …) in registration order.
  # Prefer this over legacy ["migrate"] (DO_MIGRATION well-known subset).
  default     = ["setup"]
  description = "Setup Job argv. Default [\"setup\"] runs the full registered plan. Use [\"setup\",\"migrate\",\"permissions\"] for an explicit subset; legacy [\"migrate\"] still works."
}

variable "migrate_env" {
  type        = map(string)
  default     = {}
  description = "Extra env on migrate job (merged over defaults)"
}

variable "permissions_registration" {
  type        = bool
  default     = true
  description = "Set PERMISSIONS_REGISTRATION_URL on runtime + migrate and auto-add /tenancy to OAUTH2_REQUESTED_AUDIENCES. Permission manifests publish only via setup Job (setup permissions), not runtime PreStart (Frame ≥ v2.1)."
}

# ---------------------------------------------------------------------------
# Messaging (Pub/Sub). Empty topics → default {app}-events push.
# ---------------------------------------------------------------------------

variable "create_default_events_topic" {
  type    = bool
  default = true
}

variable "messaging_topics" {
  type = map(object({
    name                       = optional(string)
    message_retention_duration = optional(string, "604800s")
  }))
  default = {}
}

variable "messaging_subscriptions" {
  type = map(object({
    topic_key                  = string
    name                       = optional(string)
    ack_deadline_seconds       = optional(number, 30)
    message_retention_duration = optional(string, "604800s")
    push_endpoint              = optional(string)
    enable_subscriber_iam      = optional(bool, true)
  }))
  default = {}
}

variable "push_oidc_audience" {
  type        = string
  default     = ""
  description = "Empty → default events push endpoint (or service URL when multi-topic)"
}

variable "create_dead_letter_topic" {
  type    = bool
  default = true
}

variable "enable_messaging" {
  type        = bool
  default     = true
  description = "When false, skip Pub/Sub + push IAM (rare)"
}

# ---------------------------------------------------------------------------
# Keep-warm (Cloud Scheduler)
# ---------------------------------------------------------------------------

variable "enable_keep_warm" {
  type    = bool
  default = false
}

variable "keep_warm_path" {
  type    = string
  default = "/healthz"
}

variable "keep_warm_schedule" {
  type    = string
  default = "*/5 * * * *"
}

variable "keep_warm_scheduler_region" {
  type    = string
  default = "europe-west1"
}
