# Global HTTPS LB + Cloudflare DNS for platform public hostnames.

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

module "lb" {
  source     = "../../../modules/cloudrun-host-lb"
  project_id = var.project_id
  name       = "edge-pl"
  region     = var.region
  labels     = var.labels

  hosts = {
    "devices.stawi.org"     = { service = "platform-devices" }
    "settings.stawi.org"    = { service = "platform-settings" }
    "geolocation.stawi.org" = { service = "platform-geolocation" }
    "files.stawi.org"       = { service = "platform-files" }
  }

  cloudflare_zone_id = var.cloudflare_zone_id
  cloudflare_proxied = var.cloudflare_proxied
}
