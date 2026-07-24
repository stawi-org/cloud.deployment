variable "app_name" {
  type        = string
  description = "Application name; becomes Neon project name prefix"
}

variable "org_id" {
  type        = string
  description = "Neon organization id (org-…); required by Neon API for project create"
}

variable "region_id" {
  type        = string
  description = "Neon region id, e.g. aws-eu-central-1"
  default     = "aws-eu-central-1"
}

variable "pg_version" {
  type    = number
  default = 16
}

variable "database_name" {
  type    = string
  default = "app"
}

variable "role_name" {
  type    = string
  default = "app"
}

variable "history_retention_seconds" {
  type        = number
  default     = 86400
  description = "PITR history window (1 day default — cost-conscious for greenfield)"
}

# Cost-safe compute defaults: scale to min CU and suspend when idle.
variable "autoscaling_min_cu" {
  type        = number
  default     = 0.25
  description = "Minimum Neon compute units (0.25 = cheapest always-available floor)"
}

variable "autoscaling_max_cu" {
  type        = number
  default     = 1
  description = "Maximum Neon compute units — raise per-app if load requires it"
}

variable "suspend_timeout_seconds" {
  type        = number
  default     = 300
  description = "Idle seconds before compute suspends (scale-to-zero-ish)"
}
