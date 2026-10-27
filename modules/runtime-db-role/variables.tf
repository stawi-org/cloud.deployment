variable "app_name" {
  type = string
}

variable "project_id" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "role" {
  type        = string
  description = "Runtime role name, a plain lower-case identifier."

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.role))
    error_message = "role must be a plain lower-case identifier."
  }
}

variable "runtime_service_account_email" {
  type        = string
  description = "Service account the service and its setup Job run as."
}

variable "pooled_secret_id" {
  type        = string
  description = "Secret holding the owner's pooled DATABASE_URL (frame-cloudrun-app database_secret_id)."
}

variable "active" {
  type        = bool
  default     = false
  description = "Connect the service as the role. Turn on only after the setup Job has created it."
}

variable "direct_secret_id" {
  type        = string
  description = "Secret holding the owner's direct DATABASE_URL (frame-cloudrun-app database_direct_secret_id). The setup Job keeps migrating as the owner."
}
