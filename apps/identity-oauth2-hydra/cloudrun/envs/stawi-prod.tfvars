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
  "serviceAccount:communications-notification@stawi-communications.iam.gserviceaccount.com",
  "serviceAccount:communications-at@stawi-communications.iam.gserviceaccount.com",
  "serviceAccount:communications-smtp@stawi-communications.iam.gserviceaccount.com",
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
  "serviceAccount:ledger-ledger@stawi-ledger.iam.gserviceaccount.com",
  "serviceAccount:ledger-billing@stawi-ledger.iam.gserviceaccount.com",
]
