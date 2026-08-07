# payment-pawapay — integration rail; shared topics owned by payment-payment.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {
  project_id = var.project_id
}

locals {
  service_run_url    = "https://${var.app_name}-${data.google_project.this.number}.${var.region}.run.app"
  prompts_topic      = "payment-pawapay-prompts"
  payments_topic     = "payment-pawapay-payments"
  prompts_ref        = "pawapay-prompts"
  payments_ref       = "pawapay-payments"
  push_oidc_audience = local.service_run_url
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
  oauth2_service_client_id = "service-payment-pawapay"
  # Multi-queue rails: shared OIDC audience = service root (not events path).
  push_oidc_audience = local.push_oidc_audience

  extra_secret_ids  = toset([
    "pawapay-api-token",
    "pawapay-signature-key-id",
    "pawapay-private-key-pem",
  ])
  extra_version_ids = toset([])
  secret_env_extra = {
    PAWAPAY_API_TOKEN = { secret = "pawapay-api-token" }
    PAWAPAY_SIGNATURE_KEY_ID = { secret = "pawapay-signature-key-id" }
    PAWAPAY_PRIVATE_KEY_PEM = { secret = "pawapay-private-key-pem" }
  }

  service_env_extra = {
    QUEUE_PAWAPAY_PROMPT_NAME  = local.prompts_ref
    QUEUE_PAWAPAY_PROMPT_URI   = "push://${local.prompts_ref}?protocol=gcppubsub"
    QUEUE_PAWAPAY_PAYMENT_NAME = local.payments_ref
    QUEUE_PAWAPAY_PAYMENT_URI  = "push://${local.payments_ref}?protocol=gcppubsub"
  }

  app_env = {
    PAYMENT_SERVICE_URI = "https://api.stawi.org/payment"
    SETTINGS_SERVICE_URI = "https://api.stawi.org/settings"
    PROFILE_SERVICE_URI = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI = "https://api.stawi.org/tenancy"
    SECURELY_RUN_SERVICE = "true"
    PROFILER_ENABLE = "false"
    FRAME_DEBUG_ENDPOINTS = "true"
    PAWAPAY_ENVIRONMENT = "production"
  }
}

# Push subscriptions on topics created by payment-payment (same project).
resource "google_pubsub_subscription" "prompts" {
  project = var.project_id
  name    = "${local.prompts_topic}-push"
  topic   = local.prompts_topic

  ack_deadline_seconds = 60
  push_config {
    push_endpoint = "${local.service_run_url}/_frame/queue/${local.prompts_ref}"
    oidc_token {
      service_account_email = module.frame.runtime_service_account_email
      audience              = local.push_oidc_audience
    }
  }
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  depends_on = [module.frame]
}

resource "google_pubsub_subscription" "payments" {
  project = var.project_id
  name    = "${local.payments_topic}-push"
  topic   = local.payments_topic

  ack_deadline_seconds = 60
  push_config {
    push_endpoint = "${local.service_run_url}/_frame/queue/${local.payments_ref}"
    oidc_token {
      service_account_email = module.frame.runtime_service_account_email
      audience              = local.push_oidc_audience
    }
  }
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  depends_on = [module.frame]
}

# Env for dual-URL Frame queue (publish side unused; subscribe via push codec).
