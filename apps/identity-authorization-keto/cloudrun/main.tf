# Ory Keto — self-contained. Parity: namespaces/identity/authorization/service-keto.yaml
# Cluster read:4466 + write:4467 → two Cloud Run services.
#
# namespaces.ts is ~73KB (over Secret Manager 64KB). Serve it from a GCS FUSE volume.
# keto.yml stays in SM (small).

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

module "db" {
  source    = "../../../modules/neon-database"
  app_name  = var.app_name
  org_id    = var.neon_org_id
  region_id = var.neon_region_id
}

# Supabase project (phase 1 of the migration). Keto uses no extensions.
# Cutover keeps DSN/DATABASE_URL on SESSION mode (prepared statements).
module "supabase_db" {
  count  = var.supabase_enabled ? 1 : 0
  source = "../../../modules/supabase-database"

  app_name = var.app_name
  org_id   = var.supabase_org_id
  region   = var.supabase_region
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = substr(replace(var.app_name, "_", "-"), 0, 28)
  display_name = "Cloud Run runtime for ${var.app_name}"
}

# Config objects larger than SM 64KB (namespaces.ts).
resource "google_storage_bucket" "config" {
  name                        = "${var.project_id}-${var.app_name}-config"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
  labels                      = var.labels

  # Config only — no public access, versioning for rollbacks.
  versioning {
    enabled = true
  }
}

resource "google_storage_bucket_object" "namespaces_ts" {
  name   = "namespaces.ts"
  bucket = google_storage_bucket.config.name
  source = "${path.module}/../files/namespaces.ts"
  # Content hash so tofu updates the object when the file changes.
  content_type = "text/plain"
}

resource "google_storage_bucket_iam_member" "runtime_object_viewer" {
  bucket = google_storage_bucket.config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.runtime.email}"
}

locals {
  # Supabase migration: staging ids in phase 1, live-value override in phase 2.
  supabase_secret_ids = var.supabase_enabled ? [
    "${var.app_name}-supabase-database-url",
    "${var.app_name}-supabase-database-url-direct",
  ] : []
  supabase_secret_values = var.supabase_enabled ? {
    "${var.app_name}-supabase-database-url"        = module.supabase_db[0].pooled_connection_uri
    "${var.app_name}-supabase-database-url-direct" = module.supabase_db[0].connection_uri
  } : {}
  db_pooled_uri = (
    var.database_cutover && var.supabase_enabled
    ? module.supabase_db[0].pooled_connection_uri
    : module.db.pooled_connection_uri
  )
  db_direct_uri = (
    var.database_cutover && var.supabase_enabled
    ? module.supabase_db[0].connection_uri
    : module.db.connection_uri
  )

  database_secret_id         = "${var.app_name}-database-url"
  database_direct_secret_id  = "${var.app_name}-database-url-direct"
  keto_yml_secret_id         = "${var.app_name}-keto-yml"
  keto_migrate_yml_secret_id = "${var.app_name}-keto-migrate-yml"
  secret_ids = setunion(
    toset([
      local.database_secret_id,
      local.database_direct_secret_id,
      local.keto_yml_secret_id,
      local.keto_migrate_yml_secret_id,
    ]),
    var.extra_secret_ids,
    toset(local.supabase_secret_ids),
  )
  version_ids = setunion(toset([
    local.database_secret_id,
    local.database_direct_secret_id,
    local.keto_yml_secret_id,
    local.keto_migrate_yml_secret_id,
  ]), toset(local.supabase_secret_ids))
  secret_values = merge(
    { (local.database_secret_id) = local.db_pooled_uri },
    { (local.database_direct_secret_id) = local.db_direct_uri },
    { (local.keto_yml_secret_id) = file("${path.module}/../files/keto.yml") },
    { (local.keto_migrate_yml_secret_id) = file("${path.module}/../files/keto-migrate.yml") },
    var.extra_secret_values,
    local.supabase_secret_values,
  )

  keto_common_env = merge(module.messaging.service_env, {
    GCP_PROJECT = var.project_id
    APP_NAME    = var.app_name
    LOG_LEVEL   = "info"
  })
  # Keto (and its gRPC/pgx stack) uses prepared statements. Neon *pooler*
  # (transaction mode) drops them → SQLSTATE 26000 "prepared statement pgx_N
  # does not exist" on TransactRelationTuples. Use the direct endpoint for DSN.
  keto_secret_env = {
    DSN                  = { secret = module.secrets.secret_ids[local.database_direct_secret_id] }
    DATABASE_URL         = { secret = module.secrets.secret_ids[local.database_direct_secret_id] }
    REPLICA_DATABASE_URL = { secret = module.secrets.secret_ids[local.database_secret_id] }
  }
  # Small keto.yml via Secret Manager file mount.
  keto_secret_volumes = {
    keto_config = {
      secret     = local.keto_yml_secret_id
      mount_path = "/etc/keto"
      file_name  = "keto.yml"
    }
  }
  # Large namespaces.ts via GCS FUSE (bucket root → /etc/keto-namespaces/).
  keto_gcs_volumes = {
    namespaces = {
      bucket     = google_storage_bucket.config.name
      mount_path = "/etc/keto-namespaces"
      read_only  = true
    }
  }

  # ---------------------------------------------------------------------------
  # Privacy: Keto is control plane (no public HTTPRoute in K8s). Cloud Run uses
  # exposure=authenticated (IAM required, no allUsers). Use exposure=private when
  # Shared VPC private path exists for all callers.
  #
  # Invokers: identity Frame runtimes + this SA (keep-warm OIDC) + optional
  # cross-project callers (ops/platform) via var.additional_invoker_members.
  # ---------------------------------------------------------------------------
  identity_runtime_account_ids = toset([
    "identity-authentication",
    "identity-identity",
    "identity-profile",
    "identity-tenancy",
    "identity-oauth2-hydra",
    substr(replace(var.app_name, "_", "-"), 0, 28), # keto runtime (self / keep-warm)
  ])
  keto_invoker_members = setunion(
    toset([
      for id in local.identity_runtime_account_ids :
      "serviceAccount:${id}@${var.project_id}.iam.gserviceaccount.com"
    ]),
    var.additional_invoker_members,
  )

  is_prod          = var.platform == "stawi-prod"
  authz_read_host  = local.is_prod ? "https://authz.stawi.org" : "https://authz.stawi.dev"
  authz_write_host = local.is_prod ? "https://authz-w.stawi.org" : "https://authz-w.stawi.dev"
  # Accept OIDC audiences for DNS hostnames (edge LB) in addition to run.app.
  keto_read_audiences  = [local.authz_read_host]
  keto_write_audiences = [local.authz_write_host]
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

module "messaging" {
  source                        = "../../../modules/pubsub"
  project_id                    = var.project_id
  app_name                      = var.app_name
  region                        = var.region
  runtime_service_account_email = google_service_account.runtime.email
  labels                        = var.labels

  # Regional storage only — Keto is not a Frame consumer (no push handler).
  allowed_persistence_regions = [var.region]
  enforce_in_transit          = false
  create_dead_letter_topic    = false
}

module "migrate" {
  source                = "../../../modules/cloudrun-migrate-job"
  name                  = "${var.app_name}-migrate"
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  service_account_email = google_service_account.runtime.email
  labels                = var.labels
  # Migrate config has no namespaces.ts requirement (runtime uses full keto.yml).
  args = ["migrate", "up", "-y", "-c", "/etc/keto/keto-migrate.yml"]
  env  = { LOG_LEVEL = "info" }
  secret_env = {
    DSN          = { secret = module.secrets.secret_ids[local.database_direct_secret_id] }
    DATABASE_URL = { secret = module.secrets.secret_ids[local.database_direct_secret_id] }
  }
  secret_volumes = {
    keto_migrate_config = {
      secret     = local.keto_migrate_yml_secret_id
      mount_path = "/etc/keto"
      file_name  = "keto-migrate.yml"
    }
  }
  depends_on = [module.secrets]
}

module "service_read" {
  source                = "../../../modules/cloudrun-service"
  name                  = "${var.app_name}-read"
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  labels                = var.labels
  service_account_email = google_service_account.runtime.email
  container_port        = 4466
  # Frame's Keto adapter uses gRPC (not REST). Cloud Run must advertise h2c so
  # the GFE speaks HTTP/2 end-to-end with the container. Keep-warm and health
  # probes still work over HTTPS (GFE ↔ client) with HTTP/2.
  use_http2        = true
  args             = ["serve", "read", "-c", "/etc/keto/keto.yml"]
  memory           = "512Mi"
  exposure         = var.exposure
  invoker_members  = local.keto_invoker_members
  custom_audiences = local.keto_read_audiences
  env              = local.keto_common_env
  secret_env       = local.keto_secret_env
  secret_volumes   = local.keto_secret_volumes
  gcs_volumes      = local.keto_gcs_volumes
  depends_on = [
    module.secrets,
    module.migrate,
    google_storage_bucket_object.namespaces_ts,
    google_storage_bucket_iam_member.runtime_object_viewer,
  ]
}

# Keep-warm with OIDC (service is not allUsers-invokable).
module "keep_warm_read" {
  source                     = "../../../modules/cloudrun-keep-warm"
  project_id                 = var.project_id
  name                       = "keep-warm-${var.app_name}-read"
  uri                        = "${module.service_read.uri}/health/ready"
  schedule                   = "*/5 * * * *"
  attempt_deadline           = "180s"
  scheduler_region           = "europe-west1"
  oidc_service_account_email = google_service_account.runtime.email
  oidc_audience              = module.service_read.uri
  depends_on                 = [module.service_read]
}

# Scheduler service agent must mint tokens as the OIDC SA.
data "google_project" "this" {
  project_id = var.project_id
}

resource "google_service_account_iam_member" "scheduler_token_creator" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}

module "service_write" {
  source                = "../../../modules/cloudrun-service"
  name                  = "${var.app_name}-write"
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  labels                = var.labels
  service_account_email = google_service_account.runtime.email
  container_port        = 4467
  args                  = ["serve", "write", "-c", "/etc/keto/keto.yml"]
  memory                = "512Mi"
  # Frame gRPC writes (tuple bootstrap / policy sync) require h2c end-to-end.
  use_http2 = true
  # Write is higher risk — same exposure mode, same invoker allow-list (tighten later).
  exposure         = var.exposure
  invoker_members  = local.keto_invoker_members
  custom_audiences = local.keto_write_audiences
  env              = local.keto_common_env
  secret_env       = local.keto_secret_env
  secret_volumes   = local.keto_secret_volumes
  gcs_volumes      = local.keto_gcs_volumes
  depends_on = [
    module.secrets,
    module.migrate,
    google_storage_bucket_object.namespaces_ts,
    google_storage_bucket_iam_member.runtime_object_viewer,
  ]
}
