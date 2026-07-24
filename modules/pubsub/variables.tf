variable "project_id" {
  type        = string
  description = "GCP project for Pub/Sub resources"
}

variable "app_name" {
  type        = string
  description = "Application name; used in default topic naming"
}

variable "region" {
  type        = string
  default     = ""
  description = "Workload region — used as sole allowed_persistence_region when set and list is empty"
}

variable "topics" {
  type = map(object({
    name                       = optional(string)
    message_retention_duration = optional(string, "604800s")
  }))
  description = "Map of logical topic keys. Empty uses default events topic."
  default     = {}
}

variable "subscriptions" {
  type = map(object({
    topic_key                  = string
    name                       = optional(string)
    ack_deadline_seconds       = optional(number, 30)
    message_retention_duration = optional(string, "604800s")
    push_endpoint              = optional(string)
    enable_subscriber_iam      = optional(bool, true)
  }))
  description = "Map of logical subscription keys. Empty uses default events subscription."
  default     = {}
}

variable "runtime_service_account_email" {
  type        = string
  description = "Cloud Run runtime SA email for publisher/subscriber IAM"
}

variable "enable_publisher_iam" {
  type        = bool
  default     = true
  description = "Grant roles/pubsub.publisher on topics to the runtime SA"
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "create_default_events_topic" {
  type        = bool
  default     = true
  description = "When topics map is empty, create {app_name}-events topic + subscription"
}

variable "allowed_persistence_regions" {
  type        = list(string)
  default     = []
  description = "Regions where Pub/Sub may store messages. Prefer the workload region only."
}

variable "enforce_in_transit" {
  type        = bool
  default     = true
  description = "When true, Pub/Sub also keeps in-transit messages in allowed regions"
}

variable "default_push_endpoint" {
  type        = string
  default     = null
  description = "If set, default subscription is push to this URL (Frame /_frame/queue/{ref})"
}

variable "push_oidc_service_account_email" {
  type        = string
  default     = ""
  description = "SA used by Pub/Sub to mint OIDC tokens for push auth (also FRAME_QUEUE_PUSH_OIDC_ALLOWED_EMAILS)"
}

variable "push_oidc_audience" {
  type        = string
  default     = ""
  description = "FRAME_QUEUE_PUSH_OIDC_AUDIENCE; defaults to default_push_endpoint (must match Pub/Sub push OIDC audience)"
}

variable "push_oidc_issuers" {
  type        = string
  default     = ""
  description = "FRAME_QUEUE_PUSH_OIDC_ISSUERS comma-list; empty → Google accounts issuers"
}

variable "push_oidc_jwks_url" {
  type        = string
  default     = ""
  description = "FRAME_QUEUE_PUSH_OIDC_JWKS_URL; empty → Google oauth2 v3 certs"
}

variable "create_dead_letter_topic" {
  type        = bool
  default     = true
  description = "Create {app}-events-dlq and attach dead-letter policy to the default push sub"
}

variable "dead_letter_max_delivery_attempts" {
  type        = number
  default     = 10
  description = "Max delivery attempts before dead-lettering"
}

variable "pubsub_service_agent_email" {
  type        = string
  default     = ""
  description = "service-{project_number}@gcp-sa-pubsub.iam.gserviceaccount.com for DLQ publish"
}
