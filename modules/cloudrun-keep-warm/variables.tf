variable "project_id" {
  type = string
}

variable "name" {
  type        = string
  description = "Scheduler job name (e.g. keep-warm-identity-oauth2-hydra)"
}

variable "uri" {
  type        = string
  description = "Full HTTPS URL to ping (health/ready or any path that reaches the container)"
}

variable "schedule" {
  type        = string
  default     = "*/5 * * * *"
  description = "Cron schedule. Every 5m stays under Cloud Run idle scale-to-zero (~15m)."
}

variable "time_zone" {
  type    = string
  default = "UTC"
}

variable "attempt_deadline" {
  type        = string
  default     = "180s"
  description = "Allow Cloud Run + Neon cold start on the first ping after long idle"
}

variable "scheduler_region" {
  type        = string
  default     = "europe-west1"
  description = "Cloud Scheduler region (does not need to match Cloud Run; EU default is widely available)"
}

variable "http_method" {
  type    = string
  default = "GET"
}

variable "paused" {
  type        = bool
  default     = false
  description = "If true, job exists but does not fire"
}

variable "enable_api" {
  type        = bool
  default     = true
  description = "Enable cloudscheduler.googleapis.com on the project"
}

variable "oidc_service_account_email" {
  type        = string
  default     = ""
  description = "If set, Scheduler sends OIDC token as this SA (required when target Cloud Run is not allUsers-invokable)."
}

variable "oidc_audience" {
  type        = string
  default     = ""
  description = "OIDC audience (defaults to job uri when empty). Must match what Cloud Run expects (usually the service URL)."
}
