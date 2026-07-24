variable "project_id" {
  type        = string
  description = "GCP project for Pub/Sub resources"
}

variable "app_name" {
  type        = string
  description = "Application name; used in default topic naming"
}

variable "topics" {
  type = map(object({
    name                       = optional(string)
    message_retention_duration = optional(string, "604800s") # 7d
  }))
  description = "Map of logical topic keys to config. Empty uses default events topic."
  default     = {}
}

variable "subscriptions" {
  type = map(object({
    topic_key                  = string
    name                       = optional(string)
    ack_deadline_seconds       = optional(number, 20)
    message_retention_duration = optional(string, "604800s")
    # Push endpoint (e.g. https://svc/_frame/queue/{ref}). Empty = pull.
    push_endpoint              = optional(string)
    enable_subscriber_iam      = optional(bool, true)
  }))
  description = "Map of logical subscription keys. Empty uses default on events topic."
  default     = {}
}

variable "runtime_service_account_email" {
  type        = string
  description = "Cloud Run runtime SA email for publisher/subscriber IAM"
}

variable "enable_publisher_iam" {
  type        = bool
  default     = true
  description = "Grant roles/pubsub.publisher on all topics to the runtime SA"
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

# When set, the default events subscription is push (to Frame /_frame/queue/{ref}).
variable "default_push_endpoint" {
  type        = string
  default     = null
  description = "If non-null, default events subscription is push to this URL"
}

variable "push_oidc_service_account_email" {
  type        = string
  default     = ""
  description = "SA for Pub/Sub push OIDC (must be able to mint tokens for Cloud Run invoker)"
}

variable "push_oidc_audience" {
  type        = string
  default     = ""
  description = "OIDC audience for push (defaults to push_endpoint when empty)"
}
