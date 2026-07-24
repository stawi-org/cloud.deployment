locals {
  env = "stawi-prod"
  # Replace with real project IDs when GCP project for Cloud Run is ready
  project_id = "stawi-cloudrun-prod"
  region     = "europe-west1"
  labels = {
    environment = "prod"
    managed-by  = "cloud-deployment"
  }
}
