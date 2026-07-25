image = "oryd/hydra:v2.2.0"
# Public edge (see docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname           = "oauth2.stawi.org"
advertise_public_hostname = true # public edge live (edge-lb-identity + oauth2.stawi.org ACTIVE)

# Admin edge hostname (IAM-authenticated — DNS does not open anonymous access)
admin_hostname           = "oauth2-w.stawi.org"
advertise_admin_hostname = true

# Cross-project runtimes that may call Hydra admin (OAuth client management, etc.)
additional_admin_invoker_members = [
  "serviceAccount:operations-audit@stawi-operations.iam.gserviceaccount.com",
  "serviceAccount:operations-formstore@stawi-operations.iam.gserviceaccount.com",
  "serviceAccount:operations-queuestore@stawi-operations.iam.gserviceaccount.com",
  "serviceAccount:operations-redirect@stawi-operations.iam.gserviceaccount.com",
  "serviceAccount:operations-thesa@stawi-operations.iam.gserviceaccount.com",
  "serviceAccount:operations-trustage@stawi-operations.iam.gserviceaccount.com",
  "serviceAccount:platform-devices@stawi-platform.iam.gserviceaccount.com",
  "serviceAccount:platform-files@stawi-platform.iam.gserviceaccount.com",
  "serviceAccount:platform-geolocation@stawi-platform.iam.gserviceaccount.com",
  "serviceAccount:platform-settings@stawi-platform.iam.gserviceaccount.com",
]
