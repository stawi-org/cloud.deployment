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
  default = 10
}

variable "min_instance_count" {
  type    = number
  default = 0
}

variable "concurrency" {
  type    = number
  default = 80
}

variable "ingress" {
  type    = string
  default = "INGRESS_TRAFFIC_ALL"
}

variable "labels" {
  type    = map(string)
  default = {}
}
