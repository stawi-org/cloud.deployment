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

  # Encryption + S3 secret IDs always declared. Prefer cluster/Vault values via
  # scripts/sync-cluster-secrets-to-gcp.sh. Only encryption-phrase is tofu-managed
  # (literal version id — never branch on sensitive S3 TF_VARs for for_each).
  extra_secret_ids = toset([
    "${var.app_name}-encryption-phrase",
    "${var.app_name}-s3-endpoint",
    "${var.app_name}-s3-access-key-id",
    "${var.app_name}-s3-access-key-secret",
  ])
  extra_version_ids = toset([
    "${var.app_name}-encryption-phrase",
  ])
  extra_secret_values = {
    "${var.app_name}-encryption-phrase" = random_password.encryption_phrase.result
  }
  secret_env_extra = {
    ENCRYPTION_PHRASE    = { secret = "${var.app_name}-encryption-phrase" }
    S3_ENDPOINT          = { secret = "${var.app_name}-s3-endpoint" }
    S3_ACCESS_KEY_ID     = { secret = "${var.app_name}-s3-access-key-id" }
    S3_ACCESS_KEY_SECRET = { secret = "${var.app_name}-s3-access-key-secret" }
  }

  # Colony service-files.yaml storage env (S3 primary; GCS/local kept for dual-path code).
  app_env = {
    STORAGE_PROVIDER     = var.storage_provider
    S3_PRIVATE_BUCKET    = var.s3_private_bucket
    S3_PUBLIC_BUCKET     = var.s3_public_bucket
    GCS_PRIVATE_BUCKET   = var.gcs_private_bucket
    GCS_PUBLIC_BUCKET    = var.gcs_public_bucket
    LOCAL_PRIVATE_BUCKET = var.local_private_bucket
    LOCAL_PUBLIC_BUCKET  = var.local_public_bucket
    # Pre-generated variants served from the anonymous public media route
    # (service-files >= v1.10.60). Sizes match the catalogue consumers:
    # thumb 96, card 480x360, hero 1200, og 1200x630 (stawi.imports
    # internal/media.Variants). Dynamic generation stays off so the request
    # path never resizes.
    THUMBNAIL_SIZES    = "32x32:crop,96x96:crop,480x360:scale,640x480:scale,1200x1200:scale,1200x630:crop"
    DYNAMIC_THUMBNAILS = "false"
  }
}

