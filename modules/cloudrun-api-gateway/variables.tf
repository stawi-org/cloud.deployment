variable "project_id" {
  type        = string
  description = "Gateway frontend project (URL map, IP, cert, DNS). Own GCP project preferred (e.g. stawi-api)."
}

variable "name" {
  type        = string
  description = "Prefix for LB resources (e.g. api-gw)"
  default     = "api-gw"
}

variable "hostname" {
  type        = string
  description = "Public API hostname (e.g. api.stawi.org)"
  default     = "api.stawi.org"
}

variable "labels" {
  type    = map(string)
  default = {}
}

# path key (unique) => backend Cloud Run in its domain project.
# NEG + backend service are created in backend_project (GCP requirement);
# the URL map in project_id references them cross-project.
variable "routes" {
  type = map(object({
    path_prefix     = string           # e.g. "/profile"
    service         = string           # Cloud Run service name
    backend_project = string           # GCP project hosting the Cloud Run service
    region          = optional(string) # defaults to var.default_region
    strip_prefix    = optional(bool, true)
    # Higher wins; 0 = auto from path length (longer prefixes first).
    priority = optional(number, 0)
  }))
  description = "PathPrefix routes under hostname → Cloud Run backends (multi-project)"

  validation {
    condition = alltrue([
      for k, r in var.routes :
      startswith(r.path_prefix, "/") && r.path_prefix != "/"
    ])
    error_message = "Each path_prefix must start with / and must not be bare / (avoid catching the whole tree)."
  }
}

variable "default_region" {
  type        = string
  description = "Default Cloud Run region for serverless NEGs"
  default     = "europe-west1"
}

variable "enable_http_redirect" {
  type        = bool
  default     = true
  description = "HTTP (port 80) → HTTPS redirect on the same IP"
}

variable "default_redirect_host" {
  type        = string
  default     = "stawi.org"
  description = "Host for unmatched paths (temporary redirect)"
}

variable "cloudflare_zone_id" {
  type        = string
  default     = ""
  description = "If set, manage Cloudflare A + ACME CNAME for hostname"
}

variable "cloudflare_proxied" {
  type        = bool
  default     = false
  description = "Orange-cloud proxy for traffic A. Keep false until cert is ACTIVE."
}

variable "cloudflare_ttl" {
  type    = number
  default = 60
}

variable "cloudflare_zone_name" {
  type        = string
  default     = "stawi.org"
  description = "Zone apex used to derive relative DNS names"
}
