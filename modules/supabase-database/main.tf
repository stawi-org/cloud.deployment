# Supabase counterpart of modules/neon-database. Provider is configured in
# the app root (multi-account): supabase access token per domain org.
#
# Connection model (docs/superpowers/specs/2026-08-31-supabase-migration-design.md):
# Cloud Run egress is IPv4 and Supabase's direct endpoint is IPv6-only, so
# BOTH URIs use the Supavisor pooler host — session mode (:5432) stands in
# for "direct" (migrate jobs' advisory locks, keto's prepared statements),
# transaction mode (:6543) is the runtime pooled URI.

# URL-safe password: alphanumeric only so the URI needs no percent-encoding.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "supabase_project" "this" {
  organization_id   = var.org_id
  name              = var.app_name
  database_password = random_password.db.result
  region            = var.region
  instance_size     = var.instance_size

  lifecycle {
    # Changing the password after creation would break the constructed URIs
    # stored in Secret Manager until the next apply; rotate deliberately.
    ignore_changes = [instance_size]
  }
}

data "supabase_pooler" "this" {
  project_ref = supabase_project.this.id
}

locals {
  project_ref = supabase_project.this.id

  # The pooler data source returns a map of mode => connection string with a
  # password placeholder. The pooler HOST varies per project (aws-0/aws-1
  # prefixes), so extract it from any returned URL rather than guessing.
  pooler_any_url = values(data.supabase_pooler.this.url)[0]
  pooler_host    = regex("@([^:/@]+)[:/]", local.pooler_any_url)[0]

  db_user = "postgres.${local.project_ref}"

  session_uri     = "postgresql://${local.db_user}:${random_password.db.result}@${local.pooler_host}:5432/${var.database_name}?sslmode=require"
  transaction_uri = "postgresql://${local.db_user}:${random_password.db.result}@${local.pooler_host}:6543/${var.database_name}?sslmode=require"
}

# ---------------------------------------------------------------------------
# PostgreSQL extensions (CREATE EXTENSION IF NOT EXISTS) — same shape as the
# neon-database module's provisioner: single idempotent script, re-runs when
# the sorted list changes. Runs over the session pooler.
# ---------------------------------------------------------------------------
resource "terraform_data" "extensions" {
  count = length(var.extensions) > 0 ? 1 : 0

  input = {
    project_ref = local.project_ref
    extensions  = join(",", sort(var.extensions))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      DATABASE_URL = local.session_uri
      EXT_LIST     = join(",", sort(var.extensions))
    }
    command = <<-EOT
      set -euo pipefail
      if [[ -z "$${DATABASE_URL}" ]]; then
        echo "ERROR: DATABASE_URL is empty" >&2
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
        psql "$${DATABASE_URL}" -v ON_ERROR_STOP=1 \
          -c "CREATE EXTENSION IF NOT EXISTS \"$${ext}\" CASCADE;"
        echo "extension ok: $${ext}"
      done
    EOT
  }

  depends_on = [supabase_project.this]
}
