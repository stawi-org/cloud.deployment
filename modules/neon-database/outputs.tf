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

# Connection URI — sensitive; prefer writing to Secret Manager in app root
output "connection_uri" {
  value     = neon_project.this.connection_uri
  sensitive = true
}

output "pooled_connection_uri" {
  description = "Prefer for Cloud Run (PgBouncer)"
  value       = neon_project.this.connection_uri_pooler
  sensitive   = true
}
