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
  type = number
  # Free Neon max is 21600 (6h); paid plans can raise this.
  default     = 21600
  description = "PITR history window in seconds (free plan max 21600)"
}

# Cost-safe compute defaults. Off by default so free Neon orgs work without
# plan upgrades; enable per-app/org when the plan allows endpoint settings.
variable "configure_endpoint_settings" {
  type        = bool
  default     = false
  description = "If true, set autoscaling CU bounds on the default endpoint"
}

variable "autoscaling_min_cu" {
  type        = number
  default     = 0.25
  description = "Minimum Neon compute units (when configure_endpoint_settings)"
}

variable "autoscaling_max_cu" {
  type        = number
  default     = 1
  description = "Maximum Neon compute units (when configure_endpoint_settings)"
}

variable "extensions" {
  type        = list(string)
  description = <<-EOT
    PostgreSQL extensions to enable with CREATE EXTENSION IF NOT EXISTS.
    Applied after the Neon database/role exist (requires psql on the apply host).

    Common Neon-supported extensions:
      - uuid-ossp, pgcrypto, pg_trgm, btree_gin, btree_gist, pg_stat_statements
      - timescaledb (Apache-2 features only; no compression)
      - postgis (and postgis_topology when needed)
    Avoid pg_search on new Neon projects (deprecated for new installs as of 2026-03).
  EOT
  default = [
    "uuid-ossp",
    "pg_stat_statements",
    "pg_trgm",
    "btree_gin",
    "btree_gist",
  ]
}
