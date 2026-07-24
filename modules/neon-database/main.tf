# Provider is configured in the app root (multi-account). This module
# uses the default neon provider configuration from the root module.
#
# Cost defaults: low CU caps + short suspend + 1-day history retention.
resource "neon_project" "this" {
  name       = var.app_name
  org_id     = var.org_id
  region_id  = var.region_id
  pg_version = var.pg_version

  history_retention_seconds = var.history_retention_seconds

  default_endpoint_settings {
    autoscaling_limit_min_cu = var.autoscaling_min_cu
    autoscaling_limit_max_cu = var.autoscaling_max_cu
    suspend_timeout_seconds  = var.suspend_timeout_seconds
  }
}

resource "neon_role" "app" {
  project_id = neon_project.this.id
  branch_id  = neon_project.this.default_branch_id
  name       = var.role_name
}

resource "neon_database" "app" {
  project_id = neon_project.this.id
  branch_id  = neon_project.this.default_branch_id
  name       = var.database_name
  owner_name = neon_role.app.name
}
