# Bootstrap pin (public GHCR). Routine rolls via cloudrun-ship.
# v1.54.60 = Frame v2.1.3 (parses ext.roles JSON arrays; required for SA IsInternalSystem).
# Do not pin v1.54.62 (Frame v2.1.0) — GetRoles ignored array roles → permissions 403.
image = "ghcr.io/antinvestor/service-authentication-tenancy:v1.54.60"

# Public surface is the path gateway only (no tenancy.stawi.org host).
# Leave empty → defaults to https://api.stawi.org/tenancy (custom_audiences + PUBLIC_BASE_URL).
public_hostname = ""

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
