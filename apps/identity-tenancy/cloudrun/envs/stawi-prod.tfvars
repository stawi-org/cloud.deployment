# Bootstrap pin (public GHCR). Routine rolls via cloudrun-ship.
image = "ghcr.io/antinvestor/service-authentication-tenancy:v1.54.62"

# Edge DNS (docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml).
# Service is exposure=authenticated — DNS ≠ anonymous public.
public_hostname = "tenancy.stawi.org"

# Cross-project runtimes that call tenancy (permissions registration, product APIs).
# Same set as keto/hydra-admin invokers.
additional_invoker_members = [
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
