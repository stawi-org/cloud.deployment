# operations-audit — Frame Cloud Run via modules/frame-cloudrun-app.

provider "neon" {
  api_key = var.neon_api_key
}

provider "supabase" {
  access_token = var.supabase_access_token
}

provider "google" {
  project = var.project_id
  region  = var.region
}


# See generated_secrets.tf.

# Supabase project (phase 1 of the migration). Base five extensions match the
# Neon defaults now that timescaledb is gone.
module "supabase_db" {
  count  = var.supabase_enabled ? 1 : 0
  source = "../../../modules/supabase-database"

  app_name = var.app_name
  org_id   = var.supabase_org_id
  region   = var.supabase_region
  extensions = [
    "uuid-ossp",
    "pg_stat_statements",
    "pg_trgm",
    "btree_gin",
    "btree_gist",
  ]
}

locals {
  # Phase-1 staging secrets: expose the Supabase URIs for the data copy
  # before cutover. Removed once the migration completes.
  supabase_secret_ids = var.supabase_enabled ? [
    "${var.app_name}-supabase-database-url",
    "${var.app_name}-supabase-database-url-direct",
  ] : []
  supabase_secret_values = var.supabase_enabled ? {
    "${var.app_name}-supabase-database-url"        = module.supabase_db[0].pooled_connection_uri
    "${var.app_name}-supabase-database-url-direct" = module.supabase_db[0].connection_uri
  } : {}
}

module "frame" {
  source = "../../../modules/frame-cloudrun-app"

  app_name   = var.app_name
  project_id = var.project_id
  region     = var.region
  platform   = var.platform
  image      = var.image
  labels     = var.labels

  identity_project_id = var.identity_project_id
  identity_region     = var.identity_region

  neon_org_id              = var.neon_org_id
  neon_region_id           = var.neon_region_id
  neon_extensions          = var.neon_extensions
  has_database             = var.has_database
  container_port           = var.container_port
  memory                   = var.memory
  migrate_args             = var.migrate_args
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths

  # Owns hydra-webhook-psk (synced from identity) + audit-signing-key.
  extra_secret_ids            = toset(concat(tolist(local.generated_secret_ids), local.supabase_secret_ids))
  extra_version_ids           = toset(concat(tolist(local.generated_secret_ids), local.supabase_secret_ids))
  extra_secret_values         = merge(local.generated_secret_values, local.supabase_secret_values)

  # Supabase migration: live-secret override in phase 2 (after data copy).
  database_url_override = (
    var.database_cutover && var.supabase_enabled
    ? module.supabase_db[0].pooled_connection_uri
    : null
  )
  database_url_direct_override = (
    var.database_cutover && var.supabase_enabled
    ? module.supabase_db[0].connection_uri
    : null
  )
  grant_oauth_signer_accessor = false
  secret_env_extra = {
    AUDIT_SIGNING_KEY = { secret = "audit-signing-key" }
  }

  app_env = {
    DATABASE_LOG_QUERIES = "true"
  }
}
