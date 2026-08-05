# platform-chat-agent — Frame Cloud Run via modules/frame-cloudrun-app.
# Source: github.com/antinvestor/service-profile/apps/chatagent
#
# Inference: sticky multi-key failover (OpenAI-compatible). Primary = Google
# Gemini OpenAI-compat surface (same pattern as opportunities crawler). Keys are
# Secret Manager values (comma-separated) — never committed.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  # SM secret shells (values seeded OOB — never in git).
  # Primary is required for LLM extract; secondary is optional until seeded.
  inference_primary_secret   = "platform-chat-agent-inference-api-keys"
  inference_secondary_secret = "platform-chat-agent-inference-secondary-api-keys"
  inference_secret_ids = toset([
    local.inference_primary_secret,
    local.inference_secondary_secret,
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

  neon_org_id    = var.neon_org_id
  neon_region_id = var.neon_region_id

  resource_path            = "/chat-agent"
  requested_audience_paths = ["/profile", "/tenancy", "/notification"]
  # Colony-era Hydra SA client id (service-chat-agent), not the Cloud Run app name.
  # Default frame mapping platform-* → service-* would also yield this; set explicitly.
  oauth2_service_client_id = "service-chat-agent"

  # Frame setup plan migrates chat_contexts / chat_sessions / chat_messages.
  migrate_args = ["setup"]
  migrate_env = {
    MIGRATION_PATH = "/migrations/0001"
  }

  use_http2                = true
  permissions_registration = true
  # Edge api.stawi.org/chat-agent proxies without a Google ID token; app-layer
  # OAuth still protects RPC methods (unauthenticated → 401, not Cloud Run 403).
  exposure = "public"
  # Frame probes (avoid broken /healthz on h2c Cloud Run)
  startup_probe_path  = "/readyz"
  liveness_probe_path = "/livez"
  # LLM extract turns need headroom vs pure evidence mode.
  memory = "1Gi"
  cpu    = "1"

  # Create SM shells; seed at least the primary keys before the revision can start.
  extra_secret_ids = local.inference_secret_ids

  secret_env_extra = {
    # Ordered primary keys: "key1,key2,key3" (sticky failover within Google).
    # REQUIRED: seed a version before Cloud Run can start this revision.
    INFERENCE_API_KEYS = { secret = local.inference_primary_secret }
    # Secondary OpenAI pool: map when seeded (see README). Shell exists via
    # extra_secret_ids so operators can add versions without a tofu change first.
    # Uncomment after: gcloud secrets versions add platform-chat-agent-inference-secondary-api-keys ...
    # INFERENCE_SECONDARY_API_KEYS = { secret = local.inference_secondary_secret }
  }

  app_env = {
    SECURELY_RUN_SERVICE = "true"
    # Omnichannel: assistant replies on non-web sessions go through Notification.
    NOTIFICATION_SERVICE_URI                      = "https://api.stawi.org/notification"
    NOTIFICATION_SERVICE_WORKLOAD_API_TARGET_PATH = "/ns/notifications/sa/service-notification"

    # --- Sticky multi-key inference (service-profile apps/chatagent/llm) ---
    # Primary: Gemini OpenAI-compat (keys in INFERENCE_API_KEYS secret).
    INFERENCE_PROVIDER = "google"
    INFERENCE_MODEL    = "gemini-2.0-flash"
    # Secondary: OpenAI after all Google keys are degraded (cooldown then prefer primary).
    # App ignores secondary until INFERENCE_SECONDARY_API_KEYS has real values.
    INFERENCE_SECONDARY_PROVIDER = "openai"
    INFERENCE_SECONDARY_MODEL    = "gpt-4o-mini"
    INFERENCE_FAILOVER_COOLDOWN  = "2m"
  }
}
