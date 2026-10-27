# finance-operations — Frame Cloud Run (fintech operations).
# Path /operations is the fintech ops API (not operations-* platform apps).
# OAUTH2_SIGNER_API_KEY uses SM secret hydra-webhook-psk (historical name; remote JWT signer, not Hydra admin).

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
  service_run_url = "https://${var.app_name}-${data.google_project.this.number}.${var.region}.run.app"
  # Payments the rail received: service-payment publishes each one to the
  # receive route whose uri is this topic, and operations books it.
  payment_received_topic = "${var.app_name}-payment-received"
  payment_received_ref   = "operations-payment-received"
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
  migrate_args             = ["setup"]
  migrate_execute          = false
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  oauth2_service_client_id = "service-operations"

  grant_oauth_signer_accessor = true
  permissions_registration    = true
  startup_probe_path          = "/readyz"
  liveness_probe_path         = "/livez"

  messaging_topics = {
    events           = { name = "${var.app_name}-events" }
    payment_received = { name = local.payment_received_topic }
  }
  messaging_subscriptions = {
    events = {
      topic_key             = "events"
      name                  = "${var.app_name}-events-push"
      push_endpoint         = "${local.service_run_url}/_frame/queue/${var.app_name}-events"
      enable_subscriber_iam = false
    }
    payment_received = {
      topic_key             = "payment_received"
      name                  = "${local.payment_received_topic}-push"
      push_endpoint         = "${local.service_run_url}/_frame/queue/${local.payment_received_ref}"
      enable_subscriber_iam = false
      ack_deadline_seconds  = 60
    }
  }

  service_env_extra = {
    OPERATIONS_PAYMENT_RECEIVED_NAME = local.payment_received_ref
    OPERATIONS_PAYMENT_RECEIVED_URI  = "push://${local.payment_received_ref}?protocol=gcppubsub"
  }

  app_env = merge({
    PROFILE_SERVICE_URI      = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI      = "https://api.stawi.org/tenancy"
    LEDGER_SERVICE_URI       = "https://api.stawi.org/ledger"
    PAYMENT_SERVICE_URI      = "https://api.stawi.org/payment"
    NOTIFICATION_SERVICE_URI = "https://api.stawi.org/notification"
    AUDIT_SERVICE_URI        = "https://api.stawi.org/audit"
    IDENTITY_SERVICE_URI     = "https://api.stawi.org/identity"
    LIMITS_SERVICE_URI       = "https://api.stawi.org/limits"
    LOAN_MGMT_SERVICE_URI    = "https://api.stawi.org/loans"
    SAVINGS_SERVICE_URI      = "https://api.stawi.org/savings"
    FUNDING_SERVICE_URI      = "https://api.stawi.org/funding"
    SECURELY_RUN_SERVICE     = "true"
  }, module.runtime_db.service_env)

  migrate_env = merge({
    TRUSTAGE_SERVICE_URI = "https://api.stawi.org/trustage"
  }, module.runtime_db.migrate_env)
  migrate_secret_env_extra = module.runtime_db.migrate_secret_env
  secret_env_extra         = module.runtime_db.service_secret_env
}

# service-payment publishes received payments to the receive route's topic.
resource "google_pubsub_topic_iam_member" "payment_publishes_received" {
  project = var.project_id
  topic   = local.payment_received_topic
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:payment-payment@stawi-payments.iam.gserviceaccount.com"

  depends_on = [module.frame]
}

# Row-level security applies to the role the service connects as; the setup
# Job keeps it (fintech pkg/dbrole). See modules/runtime-db-role.
module "runtime_db" {
  source = "../../../modules/runtime-db-role"

  app_name                      = var.app_name
  project_id                    = var.project_id
  labels                        = var.labels
  role                          = "finance_operations_rt"
  runtime_service_account_email = module.frame.runtime_service_account_email
  pooled_secret_id              = module.frame.database_secret_id
  direct_secret_id              = module.frame.database_direct_secret_id
}
