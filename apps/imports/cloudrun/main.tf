# imports — Stawi Imports API (Go Connect-RPC, repo stawilabs/stawi.imports).
# Frontend is a Cloudflare Worker on imports.stawi.org (OpenNext); this stack is
# only the backend, reached at api.stawi.org/imports via the edge Worker.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Shared secret for trustage -> imports sweep callbacks (X-Lifecycle-Token).
# Rendered into the trustage workflow definitions by the setup job and
# checked by POST /internal/lifecycle/sweep/{expire|sla|reminders}.
resource "random_password" "lifecycle_callback_token" {
  length  = 48
  special = false
}

locals {
  # Trustage (cron sweeps) + the callback base the sweeps post back to.
  # Needed by BOTH the runtime service and the setup job (workflow sync).
  lifecycle_env = {
    TRUSTAGE_URL          = "https://api.stawi.org/trustage"
    IDENTITY_URL          = "https://api.stawi.org/identity"
    PROFILE_URL           = "https://api.stawi.org/profile"
    API_INTERNAL_BASE_URL = "https://api.stawi.trade"
    # Customer/staff notifications: templates are registered by the setup job
    # (client/templates.Sync) and messages are sent at runtime.
    NOTIFICATION_URL = "https://api.stawi.org/notification"
    # Product images: stored in service-files (PUBLIC visibility) by the API
    # and served to browsers from the anonymous public media route via the
    # edge cache, never proxied through this service.
    FILES_SERVICE_URI = "https://api.stawi.org/files"
  }
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

  neon_org_id     = var.neon_org_id
  neon_region_id  = var.neon_region_id
  neon_extensions = var.neon_extensions
  has_database    = var.has_database

  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  container_port           = var.container_port
  memory                   = var.memory
  migrate_args             = var.migrate_args

  extra_secret_ids  = toset(["${var.app_name}-lifecycle-callback-token"])
  extra_version_ids = toset(["${var.app_name}-lifecycle-callback-token"])
  extra_secret_values = {
    "${var.app_name}-lifecycle-callback-token" = random_password.lifecycle_callback_token.result
  }
  # secret_env_extra is merged into the migrate/setup job too (see module).
  secret_env_extra = {
    LIFECYCLE_CALLBACK_TOKEN = { secret = "${var.app_name}-lifecycle-callback-token" }
  }

  # Structured logs so Cloud Logging parses severity (alerts key on it).
  # /readyz pings the database (imports v0.6.0+); one warm instance keeps the
  # stawi.trade SSR path off the ~2.7s cold start.
  min_instance_count  = 1
  startup_probe_path  = "/readyz"
  liveness_probe_path = "/livez"

  app_env = merge(local.lifecycle_env, {
    IMPORTS_PUBLIC_BASE_URL = "https://stawi.trade"
    FRONTEND_ORIGIN         = "https://stawi.trade"
    PROFILE_SERVICE_URI     = "https://api.stawi.org/profile"
    REQUEST_DECISION_EXPIRY = "336h"
    LOG_FORMAT              = "json"
  })
  migrate_env = merge(local.lifecycle_env, { LOG_FORMAT = "json" })
}
