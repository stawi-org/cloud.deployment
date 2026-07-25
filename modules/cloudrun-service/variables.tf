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

variable "use_http2" {
  type        = bool
  default     = false
  description = "If true, advertise h2c on the container port (required for gRPC clients on Cloud Run)"
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
    file_name = optional(string, null)
    version   = optional(string, "latest")
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
  type        = string
  default     = null
  description = "Override ingress. Prefer var.exposure unless you need a raw Cloud Run value."
  validation {
    condition = var.ingress == null || contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER",
    ], var.ingress)
    error_message = "ingress must be a valid Cloud Run v2 ingress enum or null."
  }
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "deletion_protection" {
  type    = bool
  default = false
}

# ---------------------------------------------------------------------------
# Exposure framework (prefer this over raw ingress + public_invoker)
#
# public         — internet + allUsers (or edge LB). Product APIs, Hydra public.
# authenticated  — internet path exists but IAM required (no allUsers). Control
#                  plane callable cross-project without Shared VPC (Keto, Hydra admin).
# private        — INGRESS_TRAFFIC_INTERNAL_ONLY. Same VPC / internal only.
#                  Use when Shared VPC or same-project private callers are ready.
# ---------------------------------------------------------------------------

variable "exposure" {
  type        = string
  default     = "public"
  description = "public | authenticated | private — see modules/cloudrun-service README"
  validation {
    condition     = contains(["public", "authenticated", "private"], var.exposure)
    error_message = "exposure must be public, authenticated, or private."
  }
}

variable "public_invoker" {
  type        = bool
  default     = null
  description = "Deprecated override: grant allUsers run.invoker. Null → derived from exposure (public only)."
}

variable "invoker_members" {
  type        = set(string)
  default     = []
  description = "IAM members granted roles/run.invoker (e.g. serviceAccount:app@project.iam.gserviceaccount.com). Required for authenticated/private unless empty bootstrap."
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
