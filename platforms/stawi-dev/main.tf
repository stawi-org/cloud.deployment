locals {
  env = "stawi-dev"
  # Replace with real project IDs when GCP project for Cloud Run is ready
  project_id = "stawi-cloudrun-dev"
  region     = "europe-west1"
  labels = {
    environment = "dev"
    managed-by  = "cloud-deployment"
  }
}
