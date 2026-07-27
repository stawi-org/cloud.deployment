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
  # Browser-facing OIDC (Cloudflare SSL).
  oauth2_public = local.is_prod ? "https://oauth2.stawi.org" : "https://oauth2.stawi.dev"
  api_base      = local.is_prod ? "https://api.stawi.org" : "https://api.stawi.dev"
  # Product deps: path gateway only (no profile.stawi.org / devices.* hosts).
  profile_uri = "${local.api_base}/profile"
  tenancy_uri = "${local.api_base}/tenancy"
  devices_uri = "${local.api_base}/devices"
  files_uri   = "${local.api_base}/files"
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
  min_instance_count  = 1
  enable_keep_warm    = true
  keep_warm_path      = "/healthz"
  startup_probe_path  = "/healthz"
  liveness_probe_path = "/healthz"

  # Literal ids only (never keys() of sensitive maps — OpenTofu for_each panic).
  # Google OAuth secret IDs always exist; values seeded out-of-band (Vault/k8s → SM)
  # so the public git repo never holds credentials.
  extra_secret_ids = toset(concat(
    [
      "identity-authentication-csrf-secret",
      "identity-authentication-cookie-hash-key",
      "identity-authentication-cookie-block-key",
      "identity-authentication-google-oauth-client-id",
      "identity-authentication-google-oauth-client-secret",
    ],
  ))
  # Tofu-managed versions only for secrets with values this apply (generated + optional TF_VAR).
  extra_version_ids = toset(concat(
    [
      "identity-authentication-csrf-secret",
      "identity-authentication-cookie-hash-key",
      "identity-authentication-cookie-block-key",
    ],
    var.google_oauth_client_id != "" ? ["identity-authentication-google-oauth-client-id"] : [],
    var.google_oauth_client_secret != "" ? ["identity-authentication-google-oauth-client-secret"] : [],
  ))
  # Optional bootstrap from TF_VAR (CI/local); prefer scripts/sync-cluster-secrets-to-gcp.sh
  extra_secret_values = merge(
    local.generated_secret_values,
    var.google_oauth_client_id != "" ? {
      "identity-authentication-google-oauth-client-id" = var.google_oauth_client_id
    } : {},
    var.google_oauth_client_secret != "" ? {
      "identity-authentication-google-oauth-client-secret" = var.google_oauth_client_secret
    } : {},
  )
  secret_env_extra = {
    CSRF_SECRET                    = { secret = "identity-authentication-csrf-secret" }
    SECURE_COOKIE_HASH_KEY         = { secret = "identity-authentication-cookie-hash-key" }
    SECURE_COOKIE_BLOCK_KEY        = { secret = "identity-authentication-cookie-block-key" }
    HYDRA_WEBHOOK_API_PSK          = { secret = "hydra-webhook-psk" }
    AUTH_PROVIDER_GOOGLE_CLIENT_ID = { secret = "identity-authentication-google-oauth-client-id" }
    AUTH_PROVIDER_GOOGLE_SECRET    = { secret = "identity-authentication-google-oauth-client-secret" }
  }
  # Setup plan loads OIDC + secure cookies (not a bare schema migrate).
  migrate_secret_env_extra = {
    CSRF_SECRET                    = { secret = "identity-authentication-csrf-secret" }
    SECURE_COOKIE_HASH_KEY         = { secret = "identity-authentication-cookie-hash-key" }
    SECURE_COOKIE_BLOCK_KEY        = { secret = "identity-authentication-cookie-block-key" }
    HYDRA_WEBHOOK_API_PSK          = { secret = "hydra-webhook-psk" }
    OAUTH2_SIGNER_API_KEY          = { secret = "hydra-webhook-psk" }
    AUTH_PROVIDER_GOOGLE_CLIENT_ID = { secret = "identity-authentication-google-oauth-client-id" }
    AUTH_PROVIDER_GOOGLE_SECRET    = { secret = "identity-authentication-google-oauth-client-secret" }
  }

  # Colony service-authentication.yaml env parity (path gateway for product APIs).
  app_env = {
    EXPOSE_ERRORS                      = "false"
    TRACE_REQUESTS                     = "false"
    # In-memory cache until Valkey/Memorystore is wired on GCP.
    CACHE_URI                          = "mem://defaultCache"
    PROFILE_SERVICE_URI                = local.profile_uri
    TENANCY_SERVICE_URI                = local.tenancy_uri
    DEVICE_SERVICE_URI                 = local.devices_uri
    FILES_SERVICE_URI                  = local.files_uri
    # Primary tenant/partition from cluster prod (stawi root).
    DEFAULT_TENANT_ID                  = "c2f4j7au6s7f91uqnojg"
    DEFAULT_PARTITION_ID               = "c2f4j7au6s7f91uqnokg"
    FEDCM_PUBLIC_ORIGIN = local.accounts_origin
    # Hydra public host (oauth2.stawi.org) for browser and server-side token HTTP.
    FEDCM_HYDRA_PUBLIC_URL           = local.oauth2_public
    OAUTH2_HYDRA_PUBLIC_INTERNAL_URL = local.oauth2_public
    NATIVE_CREDENTIAL_EXCHANGE_ENABLED = "true"
    AUTH_PROVIDER_GOOGLE_CALLBACK_URL  = "${local.accounts_origin}/s/social/callback"
    AUTH_PROVIDER_GOOGLE_SCOPES        = "openid email profile"
  }
}
