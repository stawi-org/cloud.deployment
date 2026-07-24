# service-authentication-tenancy — parity with namespaces/identity/tenancy/service-tenancy.yaml

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "domain" {
  source = "../../../modules/identity-domain"
  env    = var.platform
}

module "edge" {
  source = "../../../modules/edge-contract"
  env    = var.platform
}

module "db" {
  source    = "../../../modules/neon-database"
  app_name  = var.app_name
  org_id    = var.neon_org_id
  region_id = var.neon_region_id
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = substr(replace(var.app_name, "_", "-"), 0, 28)
  display_name = "Cloud Run runtime for ${var.app_name}"
}

locals {
  database_secret_id        = "${var.app_name}-database-url"
  database_direct_secret_id = "${var.app_name}-database-url-direct"
  secret_ids                = setunion(toset([local.database_secret_id, local.database_direct_secret_id]), var.extra_secret_ids)
  version_ids               = toset([local.database_secret_id, local.database_direct_secret_id])
  secret_values = merge(
    { (local.database_secret_id) = module.db.pooled_connection_uri },
    { (local.database_direct_secret_id) = module.db.connection_uri },
    var.extra_secret_values,
  )
  oauth2_env = merge(module.domain.oauth2_common, {
    OAUTH2_SERVICE_CLIENT_ID   = var.app_name
    OAUTH2_RESOURCE_AUDIENCE   = module.domain.oauth2_resource_audience["tenancy"]
    OAUTH2_REQUESTED_AUDIENCES = join(",", [
      "${module.domain.api_base}/tenancy",
      "${module.domain.api_base}/profile",
      "${module.domain.api_base}/notification",
    ])
    OAUTH2_PRIVATE_JWT_KEY = jsonencode({
      source     = "url"
      signer_url = "${module.domain.accounts_origin}/webhook/sign/private-key-jwt"
      key_id     = "hydra.openid.id-token"
    })
  })
}

module "secrets" {
  source           = "../../../modules/app-secrets"
  project_id       = var.project_id
  labels           = var.labels
  secret_ids       = local.secret_ids
  version_ids      = local.version_ids
  secret_values    = local.secret_values
  accessor_members = ["serviceAccount:${google_service_account.runtime.email}"]
}

resource "google_secret_manager_secret_iam_member" "hydra_webhook_psk" {
  project   = var.project_id
  secret_id = "hydra-webhook-psk"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

module "messaging" {
  source                        = "../../../modules/pubsub"
  project_id                    = var.project_id
  app_name                      = var.app_name
  runtime_service_account_email = google_service_account.runtime.email
  labels                        = var.labels
}

module "migrate" {
  source                = "../../../modules/cloudrun-migrate-job"
  name                  = "${var.app_name}-migrate"
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  service_account_email = google_service_account.runtime.email
  labels                = var.labels
  args                  = ["migrate"]
  timeout               = "900s"
  env = merge(module.domain.migrate_env, {
    # Self registration endpoint (public API path)
    PERMISSIONS_REGISTRATION_URL = "${module.domain.service_uris.TENANCY_SERVICE_URI}/_internal/register/permissions"
  })
  secret_env = {
    DATABASE_URL = { secret = module.secrets.secret_ids[local.database_direct_secret_id] }
  }
  depends_on = [module.secrets]
}

module "service" {
  source                = "../../../modules/cloudrun-service"
  name                  = var.app_name
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  labels                = var.labels
  service_account_email = google_service_account.runtime.email
  container_port        = 8080
  memory                = "512Mi"
  env = merge(
    module.edge.service_env,
    module.domain.frame_http,
    local.oauth2_env,
    module.domain.service_uris,
    module.domain.events_mem,
    module.domain.otel_timeouts,
    module.messaging.service_env,
    {
      GCP_PROJECT                  = var.project_id
      APP_NAME                     = var.app_name
      LOG_LEVEL                    = "INFO"
      DATABASE_LOG_QUERIES         = "False"
      SYNCHRONISE_PRIMARY_PARTITIONS = "True"
      AUTHORIZATION_MODE           = "keto"
      # Keto admin = write API (cluster KETO_SERVICE_ADMIN_URI)
      KETO_SERVICE_ADMIN_URI       = module.domain.service_uris.KETO_SERVICE_ADMIN_URI
    },
  )
  secret_env = {
    DATABASE_URL          = { secret = module.secrets.secret_ids[local.database_secret_id] }
    REPLICA_DATABASE_URL  = { secret = module.secrets.secret_ids[local.database_secret_id] }
    OAUTH2_SIGNER_API_KEY = { secret = "hydra-webhook-psk" }
  }

  depends_on = [module.secrets, module.messaging, module.migrate, google_secret_manager_secret_iam_member.hydra_webhook_psk]
}

# Hourly partition sync (cluster CronJob tenancy-sync-jobs) — Cloud Scheduler can hit this later.
# Placeholder Cloud Run Job for manual/schedule invoke.
module "sync_job" {
  source                = "../../../modules/cloudrun-migrate-job"
  name                  = "${var.app_name}-sync-partitions"
  project_id            = var.project_id
  region                = var.region
  image                 = "curlimages/curl:8.20.0"
  service_account_email = google_service_account.runtime.email
  labels                = var.labels
  args = [
    "-sS", "-X", "POST",
    "--retry", "8", "--retry-all-errors",
    "-o", "/dev/null", "-w", "%%{http_code}",
    "${module.domain.service_uris.TENANCY_SERVICE_URI}/_internal/sync/clients",
  ]
  # Do not auto-execute on every apply (hourly job); create definition only.
  execute    = false
  depends_on = [module.service]
}
