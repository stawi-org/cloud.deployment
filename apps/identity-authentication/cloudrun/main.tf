# identity-authentication — Frame Cloud Run via modules/frame-cloudrun-app.
# See generated_secrets.tf (csrf + cookie keys).

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  is_prod         = var.platform == "stawi-prod"
  accounts_origin = local.is_prod ? "https://accounts.stawi.org" : "https://accounts.stawi.dev"
}

# App-local Hydra URI for FEDCM only (frame module has its own data source).
data "google_cloud_run_v2_service" "hydra_public" {
  name     = "identity-oauth2-hydra"
  location = var.region
  project  = var.project_id
}

module "frame" {
  source = "../../../modules/frame-cloudrun-app"

  app_name   = var.app_name
  project_id = var.project_id
  region     = var.region
  platform   = var.platform
  image      = var.image
  labels     = var.labels

  identity_project_id = null
  identity_region     = null

  neon_org_id    = var.neon_org_id
  neon_region_id = var.neon_region_id

  resource_path            = "/authentication"
  requested_audience_paths = ["/profile", "/tenancy", "/devices", "/files"]
  enable_keto_admin        = false

  memory              = "1Gi"
  enable_keep_warm    = true
  keep_warm_path      = "/healthz"
  startup_probe_path  = "/healthz"
  liveness_probe_path = "/healthz"

  # Literal ids only (never keys() of sensitive maps — OpenTofu for_each panic).
  extra_secret_ids = toset([
    "identity-authentication-csrf-secret",
    "identity-authentication-cookie-hash-key",
    "identity-authentication-cookie-block-key",
  ])
  extra_secret_values = local.generated_secret_values
  secret_env_extra = merge(
    {
      CSRF_SECRET             = { secret = "identity-authentication-csrf-secret" }
      SECURE_COOKIE_HASH_KEY  = { secret = "identity-authentication-cookie-hash-key" }
      SECURE_COOKIE_BLOCK_KEY = { secret = "identity-authentication-cookie-block-key" }
      HYDRA_WEBHOOK_API_PSK   = { secret = "hydra-webhook-psk" }
    },
    var.google_oauth_client_id != "" ? {
      AUTH_PROVIDER_GOOGLE_CLIENT_ID = { secret = "identity-authentication-google-oauth-client-id" }
    } : {},
    var.google_oauth_client_secret != "" ? {
      AUTH_PROVIDER_GOOGLE_SECRET = { secret = "identity-authentication-google-oauth-client-secret" }
    } : {},
  )

  app_env = {
    FEDCM_PUBLIC_ORIGIN                = local.accounts_origin
    FEDCM_HYDRA_PUBLIC_URL             = data.google_cloud_run_v2_service.hydra_public.uri
    NATIVE_CREDENTIAL_EXCHANGE_ENABLED = "true"
  }
}
