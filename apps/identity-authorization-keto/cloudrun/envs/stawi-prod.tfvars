image = "oryd/keto:v0.12.0"

# Control plane: authenticated (no allUsers). DNS: authz.stawi.org / authz-w.stawi.org.
# See docs/SERVICE_EXPOSURE.md.
# exposure = "authenticated"

# Cross-project runtimes that call AUTHORIZATION_SERVICE_* / Keto.
# SA account_id is first 28 chars of app name (modules/frame-cloudrun-app).
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
  "serviceAccount:platform-chat-agent@stawi-platform.iam.gserviceaccount.com",
  "serviceAccount:platform-calendar@stawi-platform.iam.gserviceaccount.com",
  "serviceAccount:opportunities-ats@stawi-opportunities.iam.gserviceaccount.com",
  # communications (stawi-communications)
  "serviceAccount:communications-notification@stawi-communications.iam.gserviceaccount.com",
  "serviceAccount:communications-at@stawi-communications.iam.gserviceaccount.com",
  "serviceAccount:communications-smtp@stawi-communications.iam.gserviceaccount.com",
  # payments (stawi-payments)
  "serviceAccount:payment-payment@stawi-payments.iam.gserviceaccount.com",
  "serviceAccount:payment-mpesa@stawi-payments.iam.gserviceaccount.com",
  "serviceAccount:payment-stripe@stawi-payments.iam.gserviceaccount.com",
  "serviceAccount:payment-polar@stawi-payments.iam.gserviceaccount.com",
  "serviceAccount:payment-pawapay@stawi-payments.iam.gserviceaccount.com",
  "serviceAccount:payment-flutterwave@stawi-payments.iam.gserviceaccount.com",
  "serviceAccount:payment-jenga@stawi-payments.iam.gserviceaccount.com",
  "serviceAccount:payment-airtel@stawi-payments.iam.gserviceaccount.com",
  "serviceAccount:payment-mtn@stawi-payments.iam.gserviceaccount.com",
  "serviceAccount:checkout-checkout@stawi-payments.iam.gserviceaccount.com",
  # ledger (stawi-ledger) — ledger + billing
  "serviceAccount:ledger-ledger@stawi-ledger.iam.gserviceaccount.com",
  "serviceAccount:ledger-billing@stawi-ledger.iam.gserviceaccount.com",
]
