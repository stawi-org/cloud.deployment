# platform-devices — Frame Cloud Run via modules/frame-cloudrun-app.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
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

  resource_path            = "/devices"
  requested_audience_paths = ["/profile", "/tenancy"]

  # Cloudflare TURN secrets always declared; values from Vault/k8s via
  # scripts/sync-cluster-secrets-to-gcp.sh (not git). Optional TF_VAR bootstrap.
  extra_secret_ids = toset([
    "${var.app_name}-cloudflare-turn-token-id",
    "${var.app_name}-cloudflare-turn-api-token",
  ])
  extra_version_ids = toset(concat(
    var.cloudflare_turn_token_id != "" ? ["${var.app_name}-cloudflare-turn-token-id"] : [],
    var.cloudflare_turn_api_token != "" ? ["${var.app_name}-cloudflare-turn-api-token"] : [],
  ))
  extra_secret_values = merge(
    var.cloudflare_turn_token_id != "" ? {
      "${var.app_name}-cloudflare-turn-token-id" = var.cloudflare_turn_token_id
    } : {},
    var.cloudflare_turn_api_token != "" ? {
      "${var.app_name}-cloudflare-turn-api-token" = var.cloudflare_turn_api_token
    } : {},
  )
  secret_env_extra = {
    CLOUDFLARE_TURN_TOKEN_ID  = { secret = "${var.app_name}-cloudflare-turn-token-id" }
    CLOUDFLARE_TURN_API_TOKEN = { secret = "${var.app_name}-cloudflare-turn-api-token" }
  }

  app_env = {
    TURN_PROVIDER = "cloudflare"
    TURN_TTL      = "3600"
    # Cluster placeholders; override when real TURN infra is ready.
    TURN_SERVER_URLS   = var.turn_server_urls
    TURN_SHARED_SECRET = var.turn_shared_secret
    # Colony NATS analysis queue → default events topic until a dedicated topic exists.
    QUEUE_DEVICE_ANALYSIS_URI = "gcppubsub://${var.project_id}/${var.app_name}-events"
  }
}

