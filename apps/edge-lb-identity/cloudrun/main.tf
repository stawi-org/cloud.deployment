# Global HTTPS LB for identity public hostnames.
# Classic Cloud Run domain mapping is not available in europe-west9.

provider "google" {
  project = var.project_id
  region  = var.region
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
}
