# edge-api — path-based public API front door for Cloud Run services.
# Parity: K8s Gateway HTTPRoute on api.stawi.org with ReplacePrefixMatch "/".
#
# No Neon, no Pub/Sub. Caddy reverse-proxies path prefixes to per-app Cloud Run
# URLs (deterministic {service}-{project_number}.{region}.run.app).

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = substr(replace(var.app_name, "_", "-"), 0, 28)
  display_name = "Cloud Run runtime for ${var.app_name}"
}

locals {
  region = var.region_run

  # Catalog parity: config/public-edge.yaml api_paths
  route_backends = {
    profile = {
      path_prefix = "/profile"
      host        = "identity-profile-${var.identity_project_number}.${local.region}.run.app"
    }
    tenancy = {
      path_prefix = "/tenancy"
      host        = "identity-tenancy-${var.identity_project_number}.${local.region}.run.app"
    }
    identity = {
      path_prefix = "/identity"
      host        = "identity-identity-${var.identity_project_number}.${local.region}.run.app"
    }
    devices = {
      path_prefix = "/devices"
      host        = "platform-devices-${var.platform_project_number}.${local.region}.run.app"
    }
    settings = {
      path_prefix = "/settings"
      host        = "platform-settings-${var.platform_project_number}.${local.region}.run.app"
    }
    geolocation = {
      path_prefix = "/geolocation"
      host        = "platform-geolocation-${var.platform_project_number}.${local.region}.run.app"
    }
    files = {
      path_prefix = "/files"
      host        = "platform-files-${var.platform_project_number}.${local.region}.run.app"
    }
  }

  # handle_path strips the path prefix before proxying (matches K8s URLRewrite).
  caddy_route_blocks = join("\n\n", [
    for key, r in local.route_backends : <<-EOT
    handle_path ${r.path_prefix}* {
      reverse_proxy https://${r.host} {
        header_up Host ${r.host}
        header_up X-Forwarded-Prefix ${r.path_prefix}
        transport http {
          tls
          tls_server_name ${r.host}
        }
      }
    }
    EOT
  ])

  caddyfile = <<-EOT
  {
    admin off
    auto_https off
  }

  :8080 {
    encode gzip
    log {
      output stdout
      format console
    }

    # Frame / probes
    respond /healthz 200 {
      body "ok"
      close
    }

    ${local.caddy_route_blocks}

    respond / 404 {
      body "edge-api: unknown path — use /profile /tenancy /identity /devices /settings /geolocation /files"
      close
    }
  }
  EOT

  caddyfile_secret_id = "${var.app_name}-caddyfile"
}

resource "google_secret_manager_secret" "caddyfile" {
  project   = var.project_id
  secret_id = local.caddyfile_secret_id
  labels    = var.labels
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "caddyfile" {
  secret      = google_secret_manager_secret.caddyfile.id
  secret_data = local.caddyfile
}

resource "google_secret_manager_secret_iam_member" "caddyfile_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.caddyfile.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

module "service" {
  source                = "../../../modules/cloudrun-service"
  name                  = var.app_name
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  labels                = var.labels
  service_account_email = google_service_account.runtime.email
  container_port        = 8080
  memory                = "256Mi"
  cpu                   = "1"
  # Image ENTRYPOINT is `caddy`; config mounted at /etc/caddy/Caddyfile
  args = ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
  env = {
    APP_NAME    = var.app_name
    GCP_PROJECT = var.project_id
  }
  secret_volumes = {
    caddy_config = {
      secret     = google_secret_manager_secret.caddyfile.secret_id
      mount_path = "/etc/caddy"
      file_name  = "Caddyfile"
      version    = "latest"
    }
  }
  depends_on = [
    google_secret_manager_secret_version.caddyfile,
    google_secret_manager_secret_iam_member.caddyfile_accessor,
  ]
}

# Cheap keep-warm so first API hit after idle is snappy.
module "keep_warm" {
  source           = "../../../modules/cloudrun-keep-warm"
  project_id       = var.project_id
  name             = "keep-warm-${var.app_name}"
  uri              = "${module.service.uri}/healthz"
  schedule         = "*/5 * * * *"
  attempt_deadline = "120s"
  scheduler_region = "europe-west1"
  depends_on       = [module.service]
}

module "domain" {
  source       = "../../../modules/cloudrun-domain-mapping"
  project_id   = var.project_id
  region       = var.region
  domain       = var.public_hostname
  service_name = module.service.name
  enabled      = var.enable_domain_mapping
  depends_on   = [module.service]
}
