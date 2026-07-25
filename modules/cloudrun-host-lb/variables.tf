variable "project_id" {
  type = string
}

variable "name" {
  type        = string
  description = "Prefix for LB resources (e.g. edge-identity)"
}

variable "region" {
  type        = string
  description = "Cloud Run region for serverless NEGs"
  default     = "europe-west9"
}

# hostname => Cloud Run service name (same project)
variable "hosts" {
  type = map(object({
    service = string
  }))
  description = "Map of FQDN → Cloud Run service in this project"
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "enable_http_redirect" {
  type        = bool
  default     = true
  description = "Also create HTTP (port 80) forwarding that redirects to HTTPS"
}
