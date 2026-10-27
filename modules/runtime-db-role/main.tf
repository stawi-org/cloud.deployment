# runtime-db-role — the database role a Frame service connects as, one
# Postgres row-level security applies to.
#
# Frame isolates tenants with RLS alone, and the Neon owner role the setup Job
# migrates with has BYPASSRLS. The setup Job (fintech pkg/dbrole) keeps a
# runtime role (LOGIN, NOBYPASSRLS, table grants) from DATABASE_RUNTIME_ROLE /
# DATABASE_RUNTIME_PASSWORD; once `active`, the service's DATABASE_URL logs in
# as it on the same pooled endpoint and DATABASE_REQUIRE_RLS=true makes the
# service refuse to start on a role that bypasses RLS.
#
# Wire the outputs into frame-cloudrun-app: migrate_env, migrate_secret_env_extra,
# secret_env_extra and app_env. Kept out of frame-cloudrun-app so adopting it
# re-plans only the apps that use it.

resource "random_password" "this" {
  # Alphanumeric: it is placed in a connection URI without escaping.
  length  = 40
  special = false
}

resource "google_secret_manager_secret" "password" {
  project   = var.project_id
  secret_id = "${var.app_name}-database-runtime-password"
  labels    = var.labels
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "password" {
  secret      = google_secret_manager_secret.password.id
  secret_data = random_password.this.result
}

resource "google_secret_manager_secret_iam_member" "password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.runtime_service_account_email}"
}

# The owner's pooled URL, written by frame-cloudrun-app, gives the endpoint and
# database the runtime URL reuses.
data "google_secret_manager_secret_version" "pooled" {
  count   = var.active ? 1 : 0
  project = var.project_id
  secret  = var.pooled_secret_id
}

resource "google_secret_manager_secret" "url" {
  count     = var.active ? 1 : 0
  project   = var.project_id
  secret_id = "${var.app_name}-database-url-runtime"
  labels    = var.labels
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "url" {
  count  = var.active ? 1 : 0
  secret = google_secret_manager_secret.url[0].id
  secret_data = replace(data.google_secret_manager_secret_version.pooled[0].secret_data,
  "/^([a-z]+://)[^@]+@/", "$${1}${var.role}:${random_password.this.result}@")
}

resource "google_secret_manager_secret_iam_member" "url" {
  count     = var.active ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.url[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.runtime_service_account_email}"
}
