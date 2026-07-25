# Global HTTPS LB + Cloudflare DNS for identity public hostnames.
# Classic Cloud Run domain mapping is not available in europe-west9.

provider "google" {
  project = var.project_id
  region  = var.region
}

# Token from CI: CLOUDFLARE_API_TOKEN / TF_VAR_cloudflare_api_token
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

module "lb" {
  source     = "../../../modules/cloudrun-host-lb"
  project_id = var.project_id
  name       = "edge-id"
  region     = var.region
  labels     = var.labels

  hosts = {
    "accounts.stawi.org" = { service = "identity-authentication" }
    "oauth2.stawi.org"   = { service = "identity-oauth2-hydra" }
    "profile.stawi.org"  = { service = "identity-profile" }
    "tenancy.stawi.org"  = { service = "identity-tenancy" }
    "identity.stawi.org" = { service = "identity-identity" }
  }

  cloudflare_zone_id = var.cloudflare_zone_id
  cloudflare_proxied = var.cloudflare_proxied
}
