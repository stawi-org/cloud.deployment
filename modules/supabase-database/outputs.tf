# Output contract mirrors modules/neon-database so app roots can feed either
# module's URIs into the same Secret Manager secrets.

output "project_id" {
  description = "Supabase project ref"
  value       = supabase_project.this.id
}

output "database_name" {
  value = var.database_name
}

output "role_name" {
  value = "postgres"
}

# "Direct" equivalent: Supavisor SESSION mode (:5432) — supports session
# advisory locks (migrate jobs) and prepared statements (keto runtime).
output "connection_uri" {
  value     = local.session_uri
  sensitive = true
}

# Runtime pooled URI: Supavisor TRANSACTION mode (:6543).
output "pooled_connection_uri" {
  description = "Prefer for Cloud Run runtime (transaction pooling)"
  value       = local.transaction_uri
  sensitive   = true
}

output "extensions" {
  description = "Extensions requested (applied via terraform_data when non-empty)"
  value       = var.extensions
}
