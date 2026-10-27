# Each output names the IAM grant's secret_id, so the Cloud Run resources that
# use it wait for the grant.

output "migrate_env" {
  value = { DATABASE_RUNTIME_ROLE = var.role }
}

# frame-cloudrun-app merges secret_env_extra into the setup Job too; this
# merges after it, so the setup Job keeps migrating as the owner (direct URL)
# whatever the service connects as.
output "migrate_secret_env" {
  value = {
    DATABASE_URL              = { secret = var.direct_secret_id }
    DATABASE_RUNTIME_PASSWORD = { secret = google_secret_manager_secret_iam_member.password.secret_id }
  }
}

output "service_secret_env" {
  value = var.active ? {
    DATABASE_URL         = { secret = google_secret_manager_secret_iam_member.url[0].secret_id }
    REPLICA_DATABASE_URL = { secret = google_secret_manager_secret_iam_member.url[0].secret_id }
  } : {}
}

output "service_env" {
  value = var.active ? { DATABASE_REQUIRE_RLS = "true" } : {}
}
