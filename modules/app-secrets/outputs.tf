output "secret_ids" {
  description = "Map secret_id → secret_id (for Cloud Run secret_key_ref)"
  value       = { for k, s in google_secret_manager_secret.this : k => s.secret_id }
}

output "secret_resource_names" {
  description = "Full resource names projects/.../secrets/..."
  value       = { for k, s in google_secret_manager_secret.this : k => s.name }
}

output "secret_env_refs" {
  description = "Ready-to-merge map for cloudrun-service secret_env (env name = secret_id by default)"
  value = {
    for k, s in google_secret_manager_secret.this : k => {
      secret  = s.secret_id
      version = "latest"
    }
  }
}
