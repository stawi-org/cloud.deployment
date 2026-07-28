# checkout-checkout — on stawi-payments; signing secrets seeded OOB.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  checkout_secret_ids = toset([
    "checkout-signing-secret",
    "checkout-internal-token",
    "checkout-card-encryption-key",
  ])
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
  oauth2_service_client_id = "service-payment-checkout"

  grant_oauth_signer_accessor = true

  secret_env_extra = {
    CHECKOUT_SIGNING_SECRET      = { secret = "checkout-signing-secret" }
    CHECKOUT_INTERNAL_TOKEN      = { secret = "checkout-internal-token" }
    CHECKOUT_CARD_ENCRYPTION_KEY = { secret = "checkout-card-encryption-key" }
  }

  app_env = {
    CHECKOUT_PUBLIC_BASE_URL = "https://pay.stawi.org"
    PAYMENT_SERVICE_URI      = "https://api.stawi.org/payment"
    PROFILE_SERVICE_URI      = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI      = "https://api.stawi.org/tenancy"
    SECURELY_RUN_SERVICE     = "true"
    PROFILER_ENABLE          = "false"
    FRAME_DEBUG_ENDPOINTS    = "true"
  }
}

resource "google_secret_manager_secret_iam_member" "checkout_accessor" {
  for_each  = local.checkout_secret_ids
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.frame.runtime_service_account_email}"
}
