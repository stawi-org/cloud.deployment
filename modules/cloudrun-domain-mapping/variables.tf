variable "project_id" {
  type = string
}

variable "region" {
  type        = string
  description = "Cloud Run region of the target service"
}

variable "domain" {
  type        = string
  description = "FQDN to map (must be Google-verified for the project/user)"
}

variable "service_name" {
  type        = string
  description = "Cloud Run service name to route the domain to"
}

variable "enabled" {
  type        = bool
  default     = true
  description = "Set false until domain is verified (gcloud domains verify)"
}

variable "certificate_mode" {
  type        = string
  default     = "AUTOMATIC"
  description = "AUTOMATIC (Google-managed) or NONE"
}

variable "force_override" {
  type        = bool
  default     = false
  description = "Override existing mapping if domain was mapped elsewhere"
}
