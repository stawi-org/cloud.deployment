# Ory Keto — self-contained. Parity: namespaces/identity/authorization/service-keto.yaml
# Cluster read:4466 + write:4467 → two Cloud Run services.
#
# namespaces.ts is ~73KB (over Secret Manager 64KB). Serve it from a GCS FUSE volume.
# keto.yml stays in SM (small).

provider "neon" {
  api_key = var.neon_api_key
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
  database_secret_id        = "${var.app_name}-database-url"
  database_direct_secret_id = "${var.app_name}-database-url-direct"
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
  )
  version_ids = toset([
    local.database_secret_id,
    local.database_direct_secret_id,
    local.keto_yml_secret_id,
    local.keto_migrate_yml_secret_id,
  ])
  secret_values = merge(
    { (local.database_secret_id) = module.db.pooled_connection_uri },
    { (local.database_direct_secret_id) = module.db.connection_uri },
    { (local.keto_yml_secret_id) = file("${path.module}/../files/keto.yml") },
    { (local.keto_migrate_yml_secret_id) = file("${path.module}/../files/keto-migrate.yml") },
    var.extra_secret_values,
  )

  keto_common_env = merge(module.messaging.service_env, {
    GCP_PROJECT = var.project_id
    APP_NAME    = var.app_name
    LOG_LEVEL   = "info"
  })
  keto_secret_env = {
    DSN                  = { secret = module.secrets.secret_ids[local.database_secret_id] }
    DATABASE_URL         = { secret = module.secrets.secret_ids[local.database_secret_id] }
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
  # Image default config /home/ory/keto.yml is missing — use mounted file
  args                  = ["serve", "read", "-c", "/etc/keto/keto.yml"]
  memory                = "512Mi"
  env                   = local.keto_common_env
  secret_env            = local.keto_secret_env
  secret_volumes        = local.keto_secret_volumes
  gcs_volumes           = local.keto_gcs_volumes
  depends_on = [
    module.secrets,
    module.migrate,
    google_storage_bucket_object.namespaces_ts,
    google_storage_bucket_iam_member.runtime_object_viewer,
  ]
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
  env                   = local.keto_common_env
  secret_env            = local.keto_secret_env
  secret_volumes        = local.keto_secret_volumes
  gcs_volumes           = local.keto_gcs_volumes
  depends_on = [
    module.secrets,
    module.migrate,
    google_storage_bucket_object.namespaces_ts,
    google_storage_bucket_iam_member.runtime_object_viewer,
  ]
}
