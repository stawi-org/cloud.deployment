# api-gateway (optional GCP path LB)

> **Default production front door is the Cloudflare Worker**, not this app.  
> See [`edge/cloudflare-api-gateway`](../../edge/cloudflare-api-gateway) — ~$0–5/mo vs ~$18+/mo for a Global HTTPS LB.  
> Keep this stack only if you explicitly want Google-native edge (Armor, certs on GCP).

Unified path-based API front door for **`api.stawi.org`** on a **GCP Global HTTPS LB**.

## Architecture

```
                     ┌─────────────────────────────────────┐
  api.stawi.org      │  stawi-api (this app)               │
  ────────────────►  │  Global IP + cert + URL map         │
                     │  path rules + prefix strip          │
                     └──────────────┬──────────────────────┘
                                    │ cross-project backend refs
           ┌────────────────────────┼────────────────────────┐
           ▼                        ▼                        ▼
   stawi-identity            stawi-platform           stawi-operations
   NEG+BES → Cloud Run       NEG+BES → Cloud Run      NEG+BES → Cloud Run
   /profile /tenancy …       /devices /files …        /audit /thesa …
```

GCP rule: **serverless NEG + backend service + Cloud Run** stay in the
service’s project. The gateway project owns only the **frontend** (IP,
Certificate Manager, URL map, proxies) and references remote backends.

## Path map (prod)

| Path | Cloud Run | Project |
|------|-----------|---------|
| `/profile` | identity-profile | stawi-identity |
| `/tenancy` | identity-tenancy | stawi-identity |
| `/identity` | identity-identity | stawi-identity |
| `/devices` | platform-devices | stawi-platform |
| `/settings` | platform-settings | stawi-platform |
| `/geolocation` | platform-geolocation | stawi-platform |
| `/files` | platform-files | stawi-platform |
| `/audit` | operations-audit | stawi-operations |
| `/formstore` | operations-formstore | stawi-operations |
| `/queuestore` | operations-queuestore | stawi-operations |
| `/redirect` | operations-redirect | stawi-operations |
| `/thesa` | operations-thesa | stawi-operations |
| `/trustage` | operations-trustage | stawi-operations |

URL rewrite strips the path prefix so services keep serving at `/`
(Connect RPC: `https://api.stawi.org/profile/profile.v1.…` → service sees
`/profile.v1.…`).

## Host exceptions (not on this gateway)

Still served by per-domain host LBs (`edge-lb-*`):

| Host | Why |
|------|-----|
| `accounts.stawi.org` | Login UI (not path API) |
| `oauth2.stawi.org` | OIDC public |
| `oauth2-w.stawi.org` | Hydra admin (authenticated) |
| `authz.stawi.org` / `authz-w.stawi.org` | Keto (authenticated) |

Optional per-service hostnames (`profile.stawi.org`, …) can remain for
direct/debug access; clients should prefer `api.stawi.org/<path>`.

## Prerequisites

1. **GCP project** `stawi-api` bootstrapped:

   ```bash
   ./scripts/bootstrap-gcp-account.sh \
     --account api \
     --env stawi-prod \
     --project stawi-api \
     --region europe-west9
   ```

2. **Cross-project IAM**

   a) Gateway **deploy SA** creates NEG + backend services in domain projects:

   ```bash
   GW_SA="tofu-deploy@stawi-api.iam.gserviceaccount.com"
   for P in stawi-identity stawi-platform stawi-operations; do
     gcloud projects add-iam-policy-binding "$P" \
       --member="serviceAccount:${GW_SA}" \
       --role="roles/compute.loadBalancerAdmin"
     gcloud projects add-iam-policy-binding "$P" \
       --member="serviceAccount:${GW_SA}" \
       --role="roles/compute.networkAdmin"
     gcloud projects add-iam-policy-binding "$P" \
       --member="serviceAccount:${GW_SA}" \
       --role="roles/run.viewer"
   done
   ```

   b) Gateway project **service agent** may reference remote backend services
   (cross-project service referencing for global external ALB):

   ```bash
   API_NUM=$(gcloud projects describe stawi-api --format='value(projectNumber)')
   AGENT="serviceAccount:service-${API_NUM}@gcp-sa-backendservices.iam.gserviceaccount.com"
   for P in stawi-identity stawi-platform stawi-operations; do
     gcloud projects add-iam-policy-binding "$P" \
       --member="${AGENT}" \
       --role="roles/compute.loadBalancerServiceUser"
   done
   ```

3. Enable APIs on `stawi-api`: Compute, Certificate Manager (bootstrap covers this).

4. Repository secret **`CLOUDFLARE_API_TOKEN`** (Zone:DNS:Edit on `stawi.org`).

## Apply

```bash
gh workflow run app-apply.yml -f app=api-gateway -f env=stawi-prod
```

Watch cert:

```bash
gcloud certificate-manager certificates list --project=stawi-api --location=global
```

Smoke (after cert ACTIVE):

```bash
curl -sSI https://api.stawi.org/profile/healthz
curl -sSI https://api.stawi.org/devices/healthz
curl -sSI https://api.stawi.org/audit/healthz
```

## Module

[`modules/cloudrun-api-gateway`](../../modules/cloudrun-api-gateway)
