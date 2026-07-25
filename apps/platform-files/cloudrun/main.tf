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

  extra_secret_ids = toset(["${var.app_name}-encryption-phrase"])
  extra_secret_values = {
    "${var.app_name}-encryption-phrase" = random_password.encryption_phrase.result
  }
  secret_env_extra = {
    ENCRYPTION_PHRASE = { secret = "${var.app_name}-encryption-phrase" }
  }

  app_env = {
    STORAGE_PROVIDER  = "S3"
    S3_PRIVATE_BUCKET = "core-private-bucket"
    S3_PUBLIC_BUCKET  = "core-public-bucket"
  }

}

