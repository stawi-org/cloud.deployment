# platform-geolocation — Frame Cloud Run via modules/frame-cloudrun-app.

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
  # PostGIS required for location_points.geom (geometry type).
  neon_extensions = [
    "uuid-ossp",
    "pg_stat_statements",
    "pg_trgm",
    "btree_gin",
    "btree_gist",
    "postgis",
  ]

  resource_path            = "/geolocation"
  requested_audience_paths = ["/profile", "/tenancy"]
  app_env                  = {}

}

