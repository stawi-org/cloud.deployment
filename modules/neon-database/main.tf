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
# Prefer lakebase_text for BM25 (requires Lakebase Search enabled on the project).
#
# Requires `psql` on the machine running tofu apply (CI installs
# postgresql-client). Extensions are applied on the direct (non-pooler)
# project connection URI (same DB services use via connection_uri outputs).
#
# local-exec defaults to /bin/sh (dash on Ubuntu runners) which rejects
# `set -o pipefail` — always use bash (see cloudrun-migrate-job).
# ---------------------------------------------------------------------------

# Single provisioner for the full extension set (idempotent CREATE IF NOT EXISTS).
# Re-runs when the sorted list changes so missing extensions are repaired without
# manual taint. One script avoids parallel for_each races that left some apps
# without btree_gin / btree_gist.
#
# Shell vars must use $${NAME} (Terraform → ${NAME}) or a single $NAME that is
# not a Terraform ${...} sequence. Never use $$NAME alone for env vars — that
# becomes $NAME only if Terraform sees $$; prefer $${NAME} for clarity.
resource "terraform_data" "extensions" {
  count = length(var.extensions) > 0 ? 1 : 0

  input = {
    project_id = neon_project.this.id
    database   = neon_database.app.name
    role       = neon_role.app.name
    # Stable, sorted list so reordering alone does not re-run.
    extensions = join(",", sort(var.extensions))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      # connection_uri is sensitive; local-exec still receives the real value.
      DATABASE_URL = neon_project.this.connection_uri
      EXT_LIST     = join(",", sort(var.extensions))
    }
    command = <<-EOT
      set -euo pipefail
      if [[ -z "$${DATABASE_URL}" ]]; then
        echo "ERROR: DATABASE_URL is empty (neon_project.connection_uri unset)" >&2
        exit 1
      fi
      if ! command -v psql >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
          sudo apt-get update -qq
          sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql-client
        else
          echo "ERROR: psql not found and apt-get unavailable" >&2
          exit 1
        fi
      fi
      IFS=',' read -r -a exts <<< "$${EXT_LIST}"
      for ext in "$${exts[@]}"; do
        [[ -n "$${ext}" ]] || continue
        # Neon allows CREATE EXTENSION for supported extensions as DB owner.
        psql "$${DATABASE_URL}" -v ON_ERROR_STOP=1 \
          -c "CREATE EXTENSION IF NOT EXISTS \"$${ext}\" CASCADE;"
        echo "extension ok: $${ext}"
      done
    EOT
  }

  depends_on = [
    neon_database.app,
    neon_role.app,
  ]
}
