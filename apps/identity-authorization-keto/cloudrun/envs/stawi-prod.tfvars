image = "oryd/keto:v0.12.0"

# Control plane: authenticated (no allUsers). See docs/SERVICE_EXPOSURE.md.
# exposure = "authenticated"
#
# After ops/platform call Keto, grant their runtime SAs:
# additional_invoker_members = [
#   "serviceAccount:operations-audit@stawi-operations.iam.gserviceaccount.com",
#   "serviceAccount:operations-formstore@stawi-operations.iam.gserviceaccount.com",
#   "serviceAccount:operations-trustage@stawi-operations.iam.gserviceaccount.com",
#   "serviceAccount:platform-devices@stawi-platform.iam.gserviceaccount.com",
#   "serviceAccount:platform-settings@stawi-platform.iam.gserviceaccount.com",
# ]
