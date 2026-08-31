variable "app_name" {
  type        = string
  description = "Application name; becomes the Supabase project name"
}

variable "org_id" {
  type        = string
  description = "Supabase organization slug (Dashboard > Organization Settings > Organization slug)"
}

variable "region" {
  type        = string
  description = "Supabase region, e.g. eu-central-1 (Frankfurt; closest to Neon aws-eu-central-1)"
  default     = "eu-central-1"
}

variable "instance_size" {
  type        = string
  description = "Compute instance size (micro, small, medium, ...). Requires a paid org; leave null on the free plan."
  default     = null
}

variable "database_name" {
  type        = string
  description = "Database to connect to. Supabase projects have a single 'postgres' database."
  default     = "postgres"
}

variable "extensions" {
  type        = list(string)
  description = <<-EOT
    PostgreSQL extensions to enable with CREATE EXTENSION IF NOT EXISTS.
    Applied via psql over the session pooler once the project is healthy
    (requires psql on the apply host). Supabase preinstalls a large set;
    the base five used platform-wide (uuid-ossp, pg_stat_statements,
    pg_trgm, btree_gin, btree_gist) are all supported.
  EOT
  default     = []
}
