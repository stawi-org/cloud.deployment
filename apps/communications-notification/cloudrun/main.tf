# communications-notification — Frame Cloud Run via modules/frame-cloudrun-app.


provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}


# Mirror hydra-webhook-psk from identity (private_key_jwt webhooks).
data "google_secret_manager_secret_version" "identity_hydra_psk" {
  project = var.identity_project_id
  secret  = "hydra-webhook-psk"
  version = "latest"
}

locals {
  generated_secret_ids = toset(["hydra-webhook-psk"])
  generated_secret_values = {
    "hydra-webhook-psk" = data.google_secret_manager_secret_version.identity_hydra_psk.secret_data
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

  neon_org_id              = var.neon_org_id
  neon_region_id           = var.neon_region_id
  neon_extensions          = var.neon_extensions
  has_database             = var.has_database
  container_port           = var.container_port
  memory                   = var.memory
  migrate_args             = var.migrate_args
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  oauth2_service_client_id = "service-notification"

  extra_secret_ids            = local.generated_secret_ids
  extra_version_ids           = local.generated_secret_ids
  extra_secret_values         = local.generated_secret_values
  grant_oauth_signer_accessor = false

  app_env = {
    PROFILE_SERVICE_URI = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI = "https://api.stawi.org/tenancy"
  }
}
