# platform-chat-agent — Frame Cloud Run via modules/frame-cloudrun-app.
# Source: github.com/antinvestor/service-profile/apps/chatagent

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

  resource_path            = "/chat-agent"
  requested_audience_paths = ["/profile", "/tenancy", "/notification"]
  # Hydra client id registered for S2S callers (matching uses this audience).
  oauth2_service_client_id = "platform-chat-agent"

  # Frame setup plan migrates chat_contexts / chat_sessions / chat_messages.
  migrate_args = ["setup"]
  migrate_env = {
    MIGRATION_PATH = "/migrations/0001"
  }

  use_http2                = true
  permissions_registration = true
  memory                   = "512Mi"
  cpu                      = "1"

  app_env = {
    SECURELY_RUN_SERVICE = "true"
    # Omnichannel: assistant replies on non-web sessions go through Notification.
    NOTIFICATION_SERVICE_URI                      = "https://api.stawi.org/notification"
    NOTIFICATION_SERVICE_WORKLOAD_API_TARGET_PATH = "/ns/notifications/sa/service-notification"
    # Inference is optional; evidence-only mode works without it.
    # Seed secrets in SM and map via secret_env_extra when ready:
    # INFERENCE_API_KEY → inference-api-key
  }
}
