variable "name" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "image" {
  type = string
}

variable "container_port" {
  type        = number
  default     = 8080
  description = "Container listen port (Cloud Run sets PORT to this)"
}

variable "command" {
  type        = list(string)
  default     = null
  description = "Optional container entrypoint override"
}

variable "args" {
  type        = list(string)
  default     = null
  description = "Optional container args"
}

variable "service_account_email" {
  type        = string
  default     = null
  description = "If set, use this SA instead of creating one in the module."
}

variable "env" {
  type        = map(string)
  default     = {}
  description = "Plain environment variables"
}

variable "secret_env" {
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default     = {}
  description = "Env vars sourced from Secret Manager"
}

# Mount Secret Manager secrets as files.
variable "secret_volumes" {
  type = map(object({
    secret     = string
    mount_path = string
    # filename inside the mount (Cloud Run secret volume item path)
    file_name  = optional(string, null)
    version    = optional(string, "latest")
  }))
  default     = {}
  description = "Map of volume name → Secret Manager volume mount"
}

# Mount a GCS bucket (read-only) — use for files >64KB (SM limit).
variable "gcs_volumes" {
  type = map(object({
    bucket     = string
    mount_path = string
    read_only  = optional(bool, true)
  }))
  default     = {}
  description = "Map of volume name → GCS FUSE mount"
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "max_instance_count" {
  type    = number
  default = 5
}

variable "min_instance_count" {
  type    = number
  default = 0
}

variable "concurrency" {
  type    = number
  default = 80
}

variable "cpu_idle" {
  type    = bool
  default = true
}

variable "startup_cpu_boost" {
  type    = bool
  default = true
}

variable "ingress" {
  type    = string
  default = "INGRESS_TRAFFIC_ALL"
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "public_invoker" {
  type        = bool
  default     = true
  description = "Grant allUsers run.invoker (edge). Set false for admin-only services."
}

variable "startup_probe_path" {
  type        = string
  default     = ""
  description = "If set, HTTP startup probe on this path (e.g. /healthz)"
}

variable "liveness_probe_path" {
  type        = string
  default     = ""
  description = "If set, HTTP liveness probe on this path"
}
