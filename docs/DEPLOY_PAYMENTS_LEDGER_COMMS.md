# Deploy: communications, payments, ledger (+ billing)

Migrate cluster `communications` and **payment/ledger** workloads to **Cloud Run + Neon + Pub/Sub**.

Fintech (loans, savings, funding, operations, limits) is a separate domain — see
[DEPLOY_FINANCE.md](DEPLOY_FINANCE.md) (`stawi-finance`).

## Project split (authoritative)

| GCP project | `gcp.account` | Neon account | Apps |
|-------------|---------------|--------------|------|
| **stawi-communications** | `communications` | `communications` | `communications-notification`, `communications-at`, `communications-smtp` |
| **stawi-payments** | `payments` | `payments` | `payment-payment`, all `payment-*` rails, **`checkout-checkout`** |
| **stawi-ledger** | `ledger` | `ledger` | **`ledger-ledger`**, **`ledger-billing`** |

Checkout is **not** on ledger. Billing is **not** on payments.

Neon prefixes (`config/neon-accounts.yaml`):

- payments → `payment-`, `checkout-`
- ledger → `ledger-` (covers `ledger-ledger`, `ledger-billing`)
- communications → `communications-`

Region: **`europe-west1`**. Images: public **`ghcr.io/antinvestor/...`**.

## Prerequisites

1. GCP bootstraps merged (WIF + SOPS already under `credentials/gcp/{communications,payments,ledger}/`).
2. Neon SOPS present: `credentials/neon/{communications,payments,ledger}/auth.yaml` + repo `SOPS_AGE_KEY`.
3. Identity live (Hydra/Keto + `hydra-webhook-psk`). Domain `tofu-deploy@` SAs need `roles/secretmanager.secretAccessor` on identity `hydra-webhook-psk` (PSK mirror).
4. Seed rail/SMTP/checkout secrets (catalogs under `config/secret-catalog/`).

## Apply order

`payment-payment` **creates** shared rail Pub/Sub topics; integrations only attach push subscriptions.

```text
1. identity-authorization-keto + identity-oauth2-hydra  # invoker allow-lists
2. communications-notification
3. communications-at + communications-smtp              # seed SMTP SM first
4. payment-payment                                      # shared topics + core
5. payment-* rails + checkout-checkout
6. ledger-ledger → ledger-billing
```

```bash
for app in \
  identity-authorization-keto identity-oauth2-hydra \
  communications-notification communications-at communications-smtp \
  payment-payment \
  payment-mpesa payment-stripe payment-polar payment-pawapay \
  payment-flutterwave payment-jenga payment-airtel payment-mtn \
  checkout-checkout ledger-ledger ledger-billing
do
  gh workflow run app-apply.yml -f app="$app" -f env=stawi-prod
done
```

Re-run any rail apply that raced ahead of `payment-payment` (missing topics).

## Cross-service URIs

All product calls use the path gateway (not cluster DNS):

| Env | Value |
|-----|--------|
| `PROFILE_SERVICE_URI` | `https://api.stawi.org/profile` |
| `TENANCY_SERVICE_URI` | `https://api.stawi.org/tenancy` |
| `NOTIFICATION_SERVICE_URI` | `https://api.stawi.org/notification` |
| `PAYMENT_SERVICE_URI` | `https://api.stawi.org/payment` |
| `LEDGER_SERVICE_URI` | `https://api.stawi.org/ledger` |
| `CHECKOUT_SERVICE_URI` | `https://api.stawi.org/checkout` |
| `SETTINGS_SERVICE_URI` | `https://api.stawi.org/settings` |

OAuth/Keto: stable hosts `oauth2`, `oauth2-w`, `authz`, `authz-w` `.stawi.org` (frame module).

## Messaging (NATS → Pub/Sub)

| Flow | Topics / env |
|------|----------------|
| Notification integrators | Topics `notification-africastalking-send`, `notification-emailsmtp-send` (owned by `communications-at` / `communications-smtp`); route rows in Neon must publish `gcppubsub://stawi-communications/<topic>` |
| Payment rails | Topics owned by **`payment-payment`**: `payment-{route}-prompts` + `payment-{route}-payments`; rails attach push subscriptions only |
| Payment core | `INITIATE_PROMPT_ROUTE_URIS` → `gcppubsub://stawi-payments/payment-{route}-prompts`; polar payment link → `payment-polar-payments` |
| Billing lifecycle | `ledger-billing-subscription-lifecycle` (+ min_instance_count=1 for sweeps) |

## Edge

Routes are in `edge/cloudflare-api-gateway/config/routes.prod.json` (`enabled: false` until origins filled):

```bash
# after services Ready
cd edge/cloudflare-api-gateway && npm run refresh-origins
# set enabled:true for live routes, then
gh workflow run edge-api-gateway.yml
```

Hosted checkout UI: **`pay.stawi.org`** Cloud Run domain mapping → `checkout-checkout`
(DNS: grey CNAME `pay` → `ghs.googlehosted.com`; managed by
`edge/cloudflare-api-gateway/scripts/ensure-cf-domain-mapping-dns.mjs`). Merchant API
remains `api.stawi.org/checkout`.

## Ship (images)

After first apply, bootstrap ship WIF per project:

```bash
# payments
./scripts/bootstrap-cloudrun-ship.sh \
  --project stawi-payments \
  --project-number 131149412918 \
  --runtime-sa payment-payment,checkout-checkout,payment-mpesa,payment-stripe,payment-polar,payment-pawapay,payment-flutterwave,payment-jenga,payment-airtel,payment-mtn \
  --ship-repo antinvestor/service-payment

# ledger
./scripts/bootstrap-cloudrun-ship.sh \
  --project stawi-ledger \
  --project-number 142000360471 \
  --runtime-sa ledger-ledger,ledger-billing \
  --ship-repo antinvestor/service-payment

# communications
./scripts/bootstrap-cloudrun-ship.sh \
  --project stawi-communications \
  --project-number 278179989699 \
  --runtime-sa communications-notification,communications-at,communications-smtp \
  --ship-repo antinvestor/service-notification
```

Wire `release.yaml` in service repos to `cloudrun-ship.yml` (region `europe-west1`, GHCR only).

## Cluster cutover

After Cloud Run healthy + edge origins live, scale down Flux apps in `deployment.manifests`:

- `namespaces/communications/notification`, `integration-*`
- `namespaces/finance/payment`, `payment-*`, `checkout`, `ledger`, `billing`

Use `replicaCount: 0` / KEDA min 0 (same pattern as identity CR-only apps). Do not leave dual writers on the same Neon DB.

## Data migration

OpenTofu creates **new** Neon projects per app. Production cutover needs either:

1. Logical dump/restore from cluster CNPG → Neon, or  
2. Re-point (advanced) connection strings to migrated hosts after cutover freeze.

Route/template rows for notification must use Pub/Sub URLs after migrate.

## Verify

```bash
./.github/scripts/resolve-app-context.sh payment-payment stawi-prod
./.github/scripts/resolve-app-context.sh ledger-billing stawi-prod
./.github/scripts/resolve-app-context.sh checkout-checkout stawi-prod

gcloud run services list --project=stawi-payments --region=europe-west1
gcloud run services list --project=stawi-ledger --region=europe-west1
gcloud run services list --project=stawi-communications --region=europe-west1
```
