# Deploy: finance (fintech) → Cloud Run + Neon

Migrate cluster `namespaces/finance` workloads to **Cloud Run + Neon + Pub/Sub**
on a dedicated domain project **`stawi-finance`**.

Payments rails (`payment-*`) and ledger (`ledger-*`) already live on
`stawi-payments` / `stawi-ledger` — see [DEPLOY_PAYMENTS_LEDGER_COMMS.md](DEPLOY_PAYMENTS_LEDGER_COMMS.md).
This doc is **fintech only** (loans, savings, funding, operations, limits).

## Project split (authoritative)

| GCP project | `gcp.account` | Neon account | Apps |
|-------------|---------------|--------------|------|
| **stawi-finance** | `finance` | `finance` | `finance-loans`, `finance-savings`, `finance-funding`, `finance-operations`, `finance-limits` |

| App | Image (current cluster pin) | Path | OAuth client_id |
|-----|----------------------------|------|-----------------|
| `finance-loans` | `ghcr.io/antinvestor/service-fintech-loans:v1.96.20` | `/loans` | `service-loans` |
| `finance-savings` | `ghcr.io/antinvestor/service-fintech-savings:v1.96.20` | `/savings` | `service-savings` |
| `finance-funding` | `ghcr.io/antinvestor/service-fintech-funding:v1.96.20` | `/funding` | `service-funding` |
| `finance-operations` | `ghcr.io/antinvestor/service-fintech-operations:v1.96.20` | `/operations` | `service-operations` |
| `finance-limits` | `ghcr.io/antinvestor/service-fintech-limits:v1.96.20` | `/limits` | `service-limits` |

Neon prefixes: `finance-` only (`config/neon-accounts.yaml`).

Region: **`europe-west1`**. Setup Jobs: **`DO_SETUP=true`** + argv **`["setup"]`**
(via `modules/frame-cloudrun-app`).

**Note:** Path `/operations` is the **fintech** operations API. Platform
`operations-*` apps (trustage, formstore, …) stay on **`stawi-operations`**.

## Prerequisites

1. **Create GCP project** `stawi-finance` (billing linked).
2. **Bootstrap GCP** (WIF + tofu-deploy SA + SOPS):

```bash
./scripts/bootstrap-gcp-account.sh \
  --account finance \
  --env stawi-prod \
  --project stawi-finance \
  --region europe-west1 \
  --repo-path "$PWD"
```

3. **Create Neon org** “Stawi Finance” + org API key, then:

```bash
export API_KEY=napi_xxx
./scripts/bootstrap-neon-account.sh \
  --account finance \
  --api-key "$API_KEY" \
  --org-hint "Stawi Finance" \
  --org-id org-xxxx \
  --repo-path "$PWD"
```

4. Merge bootstrap PRs so `credentials/gcp/finance/` and
   `credentials/neon/finance/auth.yaml` exist on `main`.
5. Repo secrets: `R2_*` + `SOPS_AGE_KEY`.
6. Identity live (Hydra public + authentication JWT signer). Product apps do
   **not** call Hydra admin. They use Frame `private_key_jwt` via authentication’s
   remote signer (`accounts…/webhook/sign/private-key-jwt`). The module injects
   `OAUTH2_SIGNER_API_KEY` from Secret Manager id **`hydra-webhook-psk`**
   (historical name; same value as identity). Seed once into `stawi-finance`:

```bash
gcloud secrets versions access latest --secret=hydra-webhook-psk --project=stawi-identity \
  | gcloud secrets create hydra-webhook-psk --project=stawi-finance --data-file=-
# or: gcloud secrets versions add hydra-webhook-psk --project=stawi-finance --data-file=-
```

7. Hydra OAuth **clients** (not the webhook PSK) `service-loans`, `service-savings`,
   `service-funding`, `service-operations`, `service-limits` must exist
   (tenancy seeds / greenfield). `service-limits` is documented in authentication
   tenancy migration `20260420_service_limits.sql`.

## Apply order

```text
1. identity-authorization-keto + identity-oauth2-hydra   # invoker allow-lists if needed
2. finance-limits                                        # policy engine (few deps)
3. finance-savings
4. finance-operations
5. finance-funding
6. finance-loans                                         # depends on operations + ledger + payment
```

```bash
for app in \
  finance-limits \
  finance-savings \
  finance-operations \
  finance-funding \
  finance-loans
do
  gh workflow run app-apply.yml -f app="$app" -f env=stawi-prod
done
```

Or plan first:

```bash
gh workflow run app-plan.yml -f app=finance-loans -f env=stawi-prod
```

## Cross-service URIs

All product calls use the path gateway (not cluster DNS):

| Env | Value |
|-----|--------|
| `PROFILE_SERVICE_URI` | `https://api.stawi.org/profile` |
| `TENANCY_SERVICE_URI` | `https://api.stawi.org/tenancy` |
| `LEDGER_SERVICE_URI` | `https://api.stawi.org/ledger` |
| `PAYMENT_SERVICE_URI` | `https://api.stawi.org/payment` |
| `NOTIFICATION_SERVICE_URI` | `https://api.stawi.org/notification` |
| `OPERATIONS_SERVICE_URI` | `https://api.stawi.org/operations` (fintech ops) |
| `TRUSTAGE_SERVICE_URI` | `https://api.stawi.org/trustage` |

OAuth/Keto: stable hosts `oauth2`, `oauth2-w`, `authz`, `authz-w` `.stawi.org`.

## Messaging (NATS → Pub/Sub)

Cluster used JetStream (`finance-queue`). On Cloud Run, Frame default events use
**Pub/Sub** `{app}-events` push (module-managed). No NATS credentials on runtime.

If any fintech app still publishes to hard-coded NATS subjects, update the
service image to Frame ≥ **v2.0.10** with `gcppubsub` blank-import (same as
other cutovers) before cutover.

## Edge

Routes are stubbed in `edge/cloudflare-api-gateway/config/routes.prod.json`
with `enabled: false` until origins are filled:

```bash
# after services Ready
cd edge/cloudflare-api-gateway && npm run refresh-origins
# set enabled:true for finance routes, then
gh workflow run edge-api-gateway.yml
```

| Path | App |
|------|-----|
| `/loans` | `finance-loans` |
| `/savings` | `finance-savings` |
| `/funding` | `finance-funding` |
| `/operations` | `finance-operations` |
| `/limits` | `finance-limits` |

## Ship (images)

After first apply, bootstrap ship WIF:

```bash
./scripts/bootstrap-cloudrun-ship.sh \
  --project stawi-finance \
  --project-number <PROJECT_NUMBER> \
  --runtime-sa finance-loans,finance-savings,finance-funding,finance-operations,finance-limits \
  --ship-repo antinvestor/service-fintech
```

Wire `cloudrun-ship` in the fintech monorepo to project `stawi-finance`
(see [CLOUDRUN_SHIP.md](CLOUDRUN_SHIP.md)).

## Cluster drain (after parity)

1. Confirm Cloud Run health + setup Jobs green + edge `enabled: true`.
2. Pause Flux for `namespaces/finance` workloads (or scale to 0).
3. Do **not** delete CNPG/NATS until data migration (if any) is complete.
4. Greenfield Neon starts empty — plan dump/restore or dual-write if production
   data must move off cluster CNPG.

## Related

- [ADDING_AN_APP.md](ADDING_AN_APP.md)
- [GCP_BOOTSTRAP.md](GCP_BOOTSTRAP.md) / [NEON_BOOTSTRAP.md](NEON_BOOTSTRAP.md)
- [FRAME_CLOUDRUN_APP.md](FRAME_CLOUDRUN_APP.md)
- [DEPLOY_PAYMENTS_LEDGER_COMMS.md](DEPLOY_PAYMENTS_LEDGER_COMMS.md)


## Follow-ups / ops notes

### Permission manifests
Setup Jobs run `["setup","migrate"]` only. The `permissions` step POSTs to
`https://api.stawi.org/tenancy/_internal/register/permissions` and requires a
service JWT with the **`internal`** role (`IsInternalSystem`). Until Hydra/tenancy
service-account clients for `service-loans|savings|funding|operations|limits`
mint that claim, registration returns **403**. Re-enable with:

```hcl
migrate_args             = ["setup"]
permissions_registration = true
```

### Health probes
Frame exposes **`/readyz`** and **`/livez`** (not `/healthz`). Apps set those paths.

### Edge
Routes under `api.stawi.org` for `/loans`, `/savings`, `/funding`, `/operations`,
`/limits` are enabled after `npm run refresh-origins` against `stawi-finance`.
