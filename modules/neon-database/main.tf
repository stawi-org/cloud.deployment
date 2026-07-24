# Provider is configured in the app root (multi-account). This module
# uses the default neon provider configuration from the root module.
resource "neon_project" "this" {
  name       = var.app_name
  region_id  = var.region_id
  pg_version = var.pg_version

  history_retention_seconds = var.history_retention_seconds
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
