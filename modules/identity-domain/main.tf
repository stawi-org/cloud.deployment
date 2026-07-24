# Public identity-domain wiring mirrored from deployment.manifests/namespaces/identity.
# Cluster DNS (*.identity.svc) is replaced with public edge hosts used by auth-routes.

locals {
  is_prod = var.env == "stawi-prod"

  # Public hosts (prod). Dev can later use .dev hosts via env.
  accounts_origin = local.is_prod ? "https://accounts.stawi.org" : "https://accounts.stawi.dev"
  oauth2_origin   = local.is_prod ? "https://oauth2.stawi.org" : "https://oauth2.stawi.dev"
  api_base        = local.is_prod ? "https://api.stawi.org" : "https://api.stawi.dev"
  profile_public  = local.is_prod ? "https://profile.stawi.org" : "https://profile.stawi.dev"

  oauth_token_url = "${local.oauth2_origin}/oauth2/token"

  # Default tenant/partition from cluster authentication env
  default_tenant_id    = "c2f4j7au6s7f91uqnojg"
  default_partition_id = "c2f4j7au6s7f91uqnokg"

  # Shared OAuth2 client defaults (colony oauth2 block)
  oauth2_common = {
    OAUTH2_SERVICE_URI               = local.oauth2_origin
    OAUTH2_SERVICE_ADMIN_URI         = local.oauth2_origin # admin not dual-ported on CR yet; public issuer surface
    OAUTH2_WELL_KNOWN_OIDC_PATH      = ".well-known/openid-configuration"
    OAUTH2_AUDIENCE_BASE_URL         = local.api_base
    OAUTH2_CLIENT_ASSERTION_AUDIENCE = local.oauth_token_url
    OAUTH2_TOKEN_ENDPOINT_AUTH_METHOD = "private_key_jwt"
    OAUTH2_JWT_VERIFY_ISSUER         = local.is_prod ? "https://stawi.org" : "https://stawi.dev"
  }

  # Service mesh URIs → public Cloud Run edge (via API host + path, or dedicated host)
  service_uris = {
    PROFILE_SERVICE_URI             = "${local.api_base}/profile"
    TENANCY_SERVICE_URI             = "${local.api_base}/tenancy"
    AUTHORIZATION_SERVICE_READ_URI  = local.api_base # keto-read host TBD; use api until custom domain
    AUTHORIZATION_SERVICE_WRITE_URI = local.api_base
    KETO_SERVICE_ADMIN_URI          = local.api_base
    # Cross-domain (may 404 until those edges exist on Cloud Run)
    DEVICE_SERVICE_URI       = "${local.api_base}/devices"
    FILES_SERVICE_URI        = "${local.api_base}/files"
    NOTIFICATION_SERVICE_URI = "${local.api_base}/notification"
  }

  # Frame listens on HTTP_PORT; Cloud Run injects PORT from container_port.
  frame_http = {
    HTTP_PORT = "8080"
    PORT      = "8080"
  }

  # OTEL timeouts from cluster (endpoint from edge-contract / override)
  otel_timeouts = {
    OTEL_EXPORTER_OTLP_TIMEOUT         = "10000"
    OTEL_EXPORTER_OTLP_TRACES_TIMEOUT   = "10000"
    OTEL_EXPORTER_OTLP_METRICS_TIMEOUT  = "10000"
    OTEL_EXPORTER_OTLP_LOGS_TIMEOUT     = "10000"
    OTEL_BSP_EXPORT_TIMEOUT            = "10000"
    OTEL_BSP_MAX_QUEUE_SIZE            = "512"
    OTEL_BLRP_EXPORT_TIMEOUT           = "10000"
    OTEL_BLRP_MAX_QUEUE_SIZE           = "512"
    OTEL_METRIC_EXPORT_TIMEOUT         = "10000"
  }

  # In-process events until services import gocloud gcppubsub (cluster used NATS).
  # Pub/Sub topics still provisioned; EVENTS_QUEUE_URL stays mem for boot correctness.
  events_mem = {
    EVENTS_QUEUE_URL  = "mem://frame.events.internal._queue"
    EVENTS_QUEUE_NAME = "frame.events.internal_._queue"
  }

  migrate_env = merge(
    {
      LOG_LEVEL             = "INFO"
      TRACE_REQUESTS        = "false"
      EVENTS_QUEUE_URL      = "mem://frame.events.migrate"
      OTEL_TRACES_EXPORTER  = "none"
      OTEL_METRICS_EXPORTER = "none"
      OTEL_LOGS_EXPORTER    = "none"
    },
  )
}
