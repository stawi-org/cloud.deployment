output "accounts_origin" {
  value = local.accounts_origin
}

output "oauth2_origin" {
  value = local.oauth2_origin
}

output "api_base" {
  value = local.api_base
}

output "profile_public" {
  value = local.profile_public
}

output "oauth_token_url" {
  value = local.oauth_token_url
}

output "default_tenant_id" {
  value = local.default_tenant_id
}

output "default_partition_id" {
  value = local.default_partition_id
}

output "oauth2_common" {
  value = local.oauth2_common
}

output "service_uris" {
  value = local.service_uris
}

output "frame_http" {
  value = local.frame_http
}

output "otel_timeouts" {
  value = local.otel_timeouts
}

output "events_mem" {
  value = local.events_mem
}

output "migrate_env" {
  value = local.migrate_env
}

# Colony-style audience helpers
output "oauth2_resource_audience" {
  value = { for path in [
    "authentication", "identity", "profile", "tenancy"
    ] : path => "${local.api_base}/${path}"
  }
}

output "hydra_env" {
  description = "Ory Hydra env map matching cluster Helm config (public edge)"
  value = {
    SERVE_PUBLIC_PORT                   = "4444"
    SERVE_PUBLIC_BASE_URL               = local.oauth2_origin
    SERVE_PUBLIC_CORS_ENABLED           = "false"
    SERVE_PUBLIC_COOKIES_DOMAIN         = local.is_prod ? "stawi.org" : "stawi.dev"
    SERVE_PUBLIC_COOKIES_SAME_SITE_MODE = "Lax"
    SERVE_PUBLIC_COOKIES_SECURE         = "true"
    SERVE_PUBLIC_REQUEST_LOG_DISABLE_FOR_HEALTH = "true"

    URLS_LOGIN                 = "${local.accounts_origin}/s/login"
    URLS_CONSENT               = "${local.accounts_origin}/s/consent"
    URLS_LOGOUT                = "${local.accounts_origin}/s/logout"
    URLS_ERROR                 = "${local.accounts_origin}/error"
    URLS_POST_LOGOUT_REDIRECT  = "${local.accounts_origin}/logout-successful"
    URLS_SELF_PUBLIC           = local.oauth2_origin
    URLS_SELF_ISSUER           = local.is_prod ? "https://stawi.org" : "https://stawi.dev"
    URLS_SELF_ADMIN            = local.oauth2_origin

    WEBFINGER_OIDC_DISCOVERY_TOKEN_URL               = "${local.oauth2_origin}/oauth2/token"
    WEBFINGER_OIDC_DISCOVERY_AUTH_URL                = "${local.oauth2_origin}/oauth2/auth"
    WEBFINGER_OIDC_DISCOVERY_CLIENT_REGISTRATION_URL = "${local.oauth2_origin}/clients"
    WEBFINGER_OIDC_DISCOVERY_USERINFO_URL            = "${local.api_base}/profile/public/user/info"
    WEBFINGER_OIDC_DISCOVERY_JWKS_URL                = "${local.oauth2_origin}/.well-known/jwks.json"

    STRATEGIES_ACCESS_TOKEN = "jwt"
    STRATEGIES_SCOPE        = "wildcard"

    TTL_ACCESS_TOKEN             = "1h"
    TTL_REFRESH_TOKEN            = "2160h"
    TTL_ID_TOKEN                 = "1h"
    TTL_AUTH_CODE                = "10m"
    TTL_AUTHENTICATION_SESSION   = "2160h"
    TTL_LOGIN_CONSENT_REQUEST    = "1h"

    OAUTH2_PKCE_ENFORCED                      = "true"
    OAUTH2_PKCE_ENFORCED_FOR_PUBLIC_CLIENTS   = "true"
    OAUTH2_EXCLUDE_NOT_BEFORE_CLAIM           = "true"
    OAUTH2_MIRROR_TOP_LEVEL_CLAIMS            = "true"
    OAUTH2_HASHERS_ALGORITHM                  = "bcrypt"
    OAUTH2_HASHERS_BCRYPT_COST                = "12"
    OAUTH2_SESSION_ENCRYPT_AT_REST            = "true"
    OAUTH2_EXPOSE_INTERNAL_ERRORS             = "false"

    # Token enrichment webhook → authentication (public accounts host)
    OAUTH2_TOKEN_HOOK_URL = "${local.accounts_origin}/webhook/enrich/token"

    SQA_OPT_OUT = "true"
    LOG_LEVEL   = "warn"
    LOG_FORMAT  = "text"
  }
}
