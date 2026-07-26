# platform-files — Frame Cloud Run via modules/frame-cloudrun-app.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}


resource "random_password" "encryption_phrase" {
  length  = 32
  special = false
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

  neon_org_id    = var.neon_org_id
  neon_region_id = var.neon_region_id

  resource_path            = "/files"
  requested_audience_paths = ["/profile", "/tenancy"]

  extra_secret_ids = toset(concat(
    ["${var.app_name}-encryption-phrase"],
    var.s3_endpoint != "" ? ["${var.app_name}-s3-endpoint"] : [],
    var.s3_access_key_id != "" ? ["${var.app_name}-s3-access-key-id"] : [],
    var.s3_access_key_secret != "" ? ["${var.app_name}-s3-access-key-secret"] : [],
  ))
  extra_secret_values = merge(
    {
      "${var.app_name}-encryption-phrase" = random_password.encryption_phrase.result
    },
    var.s3_endpoint != "" ? { "${var.app_name}-s3-endpoint" = var.s3_endpoint } : {},
    var.s3_access_key_id != "" ? { "${var.app_name}-s3-access-key-id" = var.s3_access_key_id } : {},
    var.s3_access_key_secret != "" ? { "${var.app_name}-s3-access-key-secret" = var.s3_access_key_secret } : {},
  )
  secret_env_extra = merge(
    {
      ENCRYPTION_PHRASE = { secret = "${var.app_name}-encryption-phrase" }
    },
    var.s3_endpoint != "" ? {
      S3_ENDPOINT = { secret = "${var.app_name}-s3-endpoint" }
    } : {},
    var.s3_access_key_id != "" ? {
      S3_ACCESS_KEY_ID = { secret = "${var.app_name}-s3-access-key-id" }
    } : {},
    var.s3_access_key_secret != "" ? {
      S3_ACCESS_KEY_SECRET = { secret = "${var.app_name}-s3-access-key-secret" }
    } : {},
  )

  # Colony service-files.yaml storage env (S3 primary; GCS/local kept for dual-path code).
  app_env = {
    STORAGE_PROVIDER     = var.storage_provider
    S3_PRIVATE_BUCKET    = var.s3_private_bucket
    S3_PUBLIC_BUCKET     = var.s3_public_bucket
    GCS_PRIVATE_BUCKET   = var.gcs_private_bucket
    GCS_PUBLIC_BUCKET    = var.gcs_public_bucket
    LOCAL_PRIVATE_BUCKET = var.local_private_bucket
    LOCAL_PUBLIC_BUCKET  = var.local_public_bucket
  }
}

