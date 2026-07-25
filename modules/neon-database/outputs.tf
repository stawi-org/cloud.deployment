output "project_id" {
  value = neon_project.this.id
}

output "branch_id" {
  value = neon_project.this.default_branch_id
}

output "database_name" {
  value = neon_database.app.name
}

output "role_name" {
  value = neon_role.app.name
}

# Connection URI — sensitive; prefer writing to Secret Manager in app root.
# Uses the project default endpoint (owner + default DB). Matches existing
# identity/platform apps; neon_role.app / neon_database.app remain available
# for future per-app credential isolation.
output "connection_uri" {
  value     = neon_project.this.connection_uri
  sensitive = true
}

output "pooled_connection_uri" {
  description = "Prefer for Cloud Run (PgBouncer)"
  value       = neon_project.this.connection_uri_pooler
  sensitive   = true
}

output "extensions" {
  description = "Extensions requested (applied via terraform_data when non-empty)"
  value       = var.extensions
}
