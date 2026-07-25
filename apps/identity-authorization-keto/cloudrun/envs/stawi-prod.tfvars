image = "oryd/keto:v0.12.0"

# Control plane: authenticated (no allUsers). DNS: authz.stawi.org / authz-w.stawi.org.
# See docs/SERVICE_EXPOSURE.md.
# exposure = "authenticated"

# Cross-project runtimes that call AUTHORIZATION_SERVICE_* / Keto (ops + platform).
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
