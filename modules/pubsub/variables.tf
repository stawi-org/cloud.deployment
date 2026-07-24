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
    # Optional display override; default name is {app_name}-{key}
    name                        = optional(string)
    message_retention_duration  = optional(string, "604800s") # 7d
  }))
  description = "Map of logical topic keys to config. Empty uses default events topic."
  default     = {}
}

variable "subscriptions" {
  type = map(object({
    topic_key                 = string
    name                      = optional(string)
    ack_deadline_seconds      = optional(number, 20)
    message_retention_duration = optional(string, "604800s")
    # Optional push endpoint (e.g. Cloud Run URL). Empty = pull subscription.
    push_endpoint             = optional(string)
    # Grant roles/pubsub.subscriber on this subscription to runtime_sa when true
    enable_subscriber_iam     = optional(bool, true)
  }))
  description = "Map of logical subscription keys. Empty uses default pull on events topic."
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
  description = "When topics map is empty, create {app_name}-events with a pull subscription"
}
