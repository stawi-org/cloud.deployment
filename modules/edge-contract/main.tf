locals {
  api_hosts = [
    "https://api.stawi.org",
    "https://api.stawi.dev",
  ]
  oauth_token_url = "https://oauth2.stawi.org/oauth2/token"
  cors_allow_origins = [
    "https://admin.stawi.org",
    "https://admin.stawi.dev",
    "https://admin-dev.stawi.dev",
    "https://admin-dev.stawi.org",
    "https://thesa.stawi.org",
    "https://thesa-dev.stawi.org",
    "https://opportunities.stawi.org",
    "https://opportunities.stawi.dev",
    "https://accounts.stawi.org",
    "https://accounts.stawi.dev",
    "https://imports.stawi.org",
    "https://stawi.trade",
    "https://api.stawi.trade",
    "https://stawi.loan",
    "http://localhost:5173",
    "http://localhost:3000",
  ]
  # Minimal shared edge defaults; apps set domain-specific env themselves.
  service_env = {
    OAUTH2_SERVICE_URI               = "https://oauth2.stawi.org"
    OAUTH2_AUDIENCE_BASE_URL         = "https://api.stawi.org"
    OAUTH2_CLIENT_ASSERTION_AUDIENCE = local.oauth_token_url
    OAUTH2_CLIENT_ASSERTION_AUD      = local.oauth_token_url # legacy alias
    OTEL_EXPORTER_OTLP_ENDPOINT      = "https://otlp.nr-data.net"
    EDGE_ENV                         = var.env
  }
}
