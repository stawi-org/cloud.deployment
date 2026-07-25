# Global HTTPS LB for platform public hostnames.
# Classic Cloud Run domain mapping is not available in europe-west9.

provider "google" {
  project = var.project_id
  region  = var.region
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
}
