# Provider is configured in the app root (multi-account). This module
# uses the default neon provider configuration from the root module.
#
# Cost defaults: low CU caps + short suspend + free-plan history retention.
resource "neon_project" "this" {
  name       = var.app_name
  org_id     = var.org_id
  region_id  = var.region_id
  pg_version = var.pg_version

  history_retention_seconds = var.history_retention_seconds

  # Free Neon orgs cannot set custom suspend intervals. Only set CU bounds when enabled.
  dynamic "default_endpoint_settings" {
    for_each = var.configure_endpoint_settings ? [1] : []
    content {
      autoscaling_limit_min_cu = var.autoscaling_min_cu
      autoscaling_limit_max_cu = var.autoscaling_max_cu
      # omit suspend_timeout_seconds — not permitted on free plans; Neon default applies
    }
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

# ---------------------------------------------------------------------------
# PostgreSQL extensions (CREATE EXTENSION IF NOT EXISTS)
#
# Neon supports many extensions (timescaledb Apache-2, postgis, uuid-ossp, …).
# pg_search is deprecated on Neon for new projects (as of 2026-03) — avoid.
#
# Requires `psql` on the machine running tofu apply (CI installs
# postgresql-client). Extensions are applied on the direct (non-pooler)
# project connection URI (same DB services use via connection_uri outputs).
#
# local-exec defaults to /bin/sh (dash on Ubuntu runners) which rejects
# `set -o pipefail` — always use bash (see cloudrun-migrate-job).
# ---------------------------------------------------------------------------

resource "terraform_data" "extensions" {
  for_each = toset(var.extensions)

  input = {
    project_id = neon_project.this.id
    database   = neon_database.app.name
    extension  = each.key
    role       = neon_role.app.name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      DATABASE_URL = neon_project.this.connection_uri
      EXT_NAME     = each.key
    }
    # Quote extension names that need it (e.g. uuid-ossp).
    command = <<-EOT
      set -euo pipefail
      if ! command -v psql >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
          sudo apt-get update -qq
          sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql-client
        else
          echo "ERROR: psql not found and apt-get unavailable" >&2
          exit 1
        fi
      fi
      # Neon allows CREATE EXTENSION for supported extensions as DB owner.
      psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
        -c "CREATE EXTENSION IF NOT EXISTS \"$${EXT_NAME}\" CASCADE;"
      echo "extension ok: $${EXT_NAME}"
    EOT
  }

  depends_on = [
    neon_database.app,
    neon_role.app,
  ]
}
