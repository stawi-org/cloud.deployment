variable "app_name" {
  type        = string
  description = "Application name; becomes Neon project name prefix"
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
  type    = number
  default = 86400
}
