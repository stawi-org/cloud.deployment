# Region migration: `europe-west9` → `europe-west1`

**Why:** Cloud Run **domain mapping** works in `europe-west1` (Belgium), not in `europe-west9` (Paris, 501).  
**Scope:** all prod accounts that were on west9 — **identity**, **platform**, **operations**, **api**.  
**Neon:** stays `aws-eu-central-1` (Frankfurt) — still low latency to Belgium.

This is a **recreate** of regional resources. Cloud Run services are **not** movable in place.

---

## 0. Preflight

| Check | Command / note |
|-------|----------------|
| Domain mapping API in target | `gcloud beta run domain-mappings list --region=europe-west1 --project=stawi-identity` → lists (not 501) |
| Search Console | `stawi.org` verified for the Google user/SA that creates mappings |
| Repo config | `config/gcp-accounts.yaml` regions = `europe-west1` for prod identity/platform/operations/api |
| CI region source | `load-sops-credentials.sh` prefers **registry** region over SOPS |
| Images | Prefer `ghcr.io/antinvestor/...` (no AR region pin). Optional AR mirror in west1 |
| Freeze | Pause non-critical ships during cutover |

### Inventory (prod, west9 today)

```bash
for p in stawi-identity stawi-platform stawi-operations; do
  echo "==== $p ===="
  gcloud run services list --project=$p --region=europe-west9 --format='table(metadata.name,status.url)'
  gcloud run jobs list --project=$p --region=europe-west9 --format='table(metadata.name)' 2>/dev/null || true
done
```

---

## 1. Code / config (this repo) — done when merged

| Area | Change |
|------|--------|
| `config/gcp-accounts.yaml` | prod regions → `europe-west1` |
| `config/public-edge.yaml` | region → `europe-west1` |
| Module/app defaults | `europe-west1` |
| Edge `routes.prod.json` / refresh-origins | region `europe-west1` |
| Workflows defaults | `europe-west1` |
| Docs | ship, deploy, SSL policy, this runbook |
| CI | registry region wins over SOPS |

**Optional SOPS hygiene** (when you have `SOPS_AGE_KEY`):

```bash
export SOPS_AGE_KEY=…
for f in credentials/gcp/{identity,platform,operations}/stawi-prod/auth.yaml; do
  sops set "$f" '["auth"]["region"]' '"europe-west1"'
done
```

Not required for CI after the registry-preference change.

---

## 2. Artifact Registry (optional)

Existing repos:

- `europe-west9-docker.pkg.dev/stawi-identity/apps`
- `europe-west9-docker.pkg.dev/stawi-platform/apps`

Cloud Run in west1 **can pull** west9 AR (cross-region). For cleanliness:

```bash
for proj in stawi-identity stawi-platform; do
  gcloud artifacts repositories create apps \
    --project=$proj --repository-format=docker \
    --location=europe-west1 \
    --description="Apps (europe-west1)" || true
done
# mirror-ghcr-to-ar.sh LOCATION default is now europe-west1
```

Primary ship path remains **public GHCR** — AR is optional.

---

## 3. OpenTofu apply order (destroy west9 / create west1)

Region is an attribute of each Cloud Run service. Changing `var.region` forces **destroy + create**. Plan carefully.

### 3a. Identity control plane first

Order matters for login:

1. `identity-oauth2-hydra` (public + admin services)  
2. `identity-authorization-keto`  
3. `identity-authentication`  
4. `identity-profile`, `identity-tenancy`, `identity-identity`  
5. `edge-lb-identity` (keep `hosts={}` unless you need LB fallback)

```bash
for app in identity-oauth2-hydra identity-authorization-keto identity-authentication \
           identity-profile identity-tenancy identity-identity edge-lb-identity; do
  gh workflow run app-apply.yml -f app=$app -f env=stawi-prod
  # wait for success before next
done
```

**Expect downtime** on each service during recreate (seconds–minutes).  
DB (Neon) is external — data preserved; only Cloud Run / jobs / regional Pub/Sub topics move.

### 3b. Platform

```bash
for app in platform-devices platform-settings platform-geolocation platform-files edge-lb-platform; do
  gh workflow run app-apply.yml -f app=$app -f env=stawi-prod
done
```

### 3c. Operations

```bash
for app in operations-audit operations-formstore operations-queuestore \
           operations-redirect operations-thesa operations-trustage edge-lb-operations; do
  gh workflow run app-apply.yml -f app=$app -f env=stawi-prod
done
```

### 3d. Edge Worker origins

After services exist in west1, URLs change (`*.europe-west1.run.app` / new `*.a.run.app` hashes):

```bash
cd edge/cloudflare-api-gateway
# With gcloud auth for all backend projects:
npm run refresh-origins   # rewrites routes.prod.json origins
gh workflow run edge-api-gateway.yml -f smoke=true
```

Or commit refreshed origins and let the edge workflow deploy.

### 3e. Ship workflows (service repos)

Update **antinvestor** `cloudrun-ship` callers:

```text
region: europe-west1
```

(was `europe-west9` in each service repo / org vars).

---

## 4. Domain mappings (goal of the move)

After each target service is **Ready** in `europe-west1`:

| FQDN | Service | Project |
|------|---------|---------|
| `accounts.stawi.org` | `identity-authentication` | stawi-identity |
| `oauth2.stawi.org` | `identity-oauth2-hydra` | stawi-identity |
| `oauth2-w.stawi.org` | `identity-oauth2-hydra-admin` | stawi-identity |
| `authz.stawi.org` | `identity-authorization-keto-read` | stawi-identity |
| `authz-w.stawi.org` | `identity-authorization-keto-write` | stawi-identity |

```bash
PROJECT=stawi-identity
REGION=europe-west1

# Verify base domain once
gcloud domains list-user-verified
# gcloud domains verify stawi.org   # if needed

create_map() {
  local svc=$1 domain=$2
  gcloud beta run domain-mappings create \
    --service="$svc" --domain="$domain" \
    --region="$REGION" --project="$PROJECT" \
    --force-override 2>/dev/null \
  || gcloud beta run domain-mappings create \
    --service="$svc" --domain="$domain" \
    --region="$REGION" --project="$PROJECT"
  gcloud beta run domain-mappings describe --domain="$domain" \
    --region="$REGION" --project="$PROJECT"
}

create_map identity-authentication accounts.stawi.org
create_map identity-oauth2-hydra oauth2.stawi.org
create_map identity-oauth2-hydra-admin oauth2-w.stawi.org
create_map identity-authorization-keto-read authz.stawi.org
create_map identity-authorization-keto-write authz-w.stawi.org
```

Install **every** `resourceRecords` entry in Cloudflare DNS.

**Cloudflare tips** (Google docs):

- Avoid orange-cloud intercepting ACME if cert stuck — often **DNS only (grey)** for mapped hosts, or disable “Always Use HTTPS” during first issue  
- Once cert is **ACTIVE**, orange is optional for CDN  

Confirm:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://oauth2.stawi.org/health/ready
# IAM hosts without token may 403 — good if TLS works
curl -sS -o /dev/null -w "%{http_code}\n" https://oauth2-w.stawi.org/health/ready
```

With ID token audience `https://oauth2-w.stawi.org` → expect **200**.

### Custom audiences

Already configured on hydra admin / keto via `custom_audiences` for `https://oauth2-w.stawi.org` etc.  
Re-apply apps if missing after recreate.

---

## 5. Tear down west9 leftovers

Only after west1 is healthy and DNS points to new mappings:

```bash
# List anything still in west9
gcloud run services list --project=stawi-identity --region=europe-west9
# OpenTofu apply with region=west1 should already have destroyed west9 services
# if state tracked them. Orphans (manual):
# gcloud run services delete NAME --region=europe-west9 --project=...
```

Optional: delete old AR `europe-west9` repos after images are unused.

---

## 6. Verification checklist

| Test | Expect |
|------|--------|
| `gcloud run services list --region=europe-west1 --project=stawi-identity` | All identity services |
| `gcloud run services list --region=europe-west9 --project=stawi-identity` | Empty (or only deleted) |
| `https://accounts.stawi.org/readyz` | 200 |
| `https://oauth2.stawi.org/health/ready` | 200 |
| `https://oauth2-w.stawi.org/health/ready` + ID token | 200 |
| Login challenge flow | HTML sign-in, not “temporarily unavailable” |
| `https://api.stawi.org/_gateway/health` | 200; path routes proxy to new origins |
| Keto S2S from a Frame app | No authz connect errors |
| Domain mapping status | Ready / certificate active |

---

## 7. Rollback

1. Point DNS back to previous records (CF history / run.app CNAME + Worker fallback).  
2. Re-apply apps with `region=europe-west9` in `gcp-accounts.yaml` (recreates west9).  
3. Ship repos region pin back to west9.  

Neon data is unchanged either way.

---

## 8. Risk summary

| Risk | Mitigation |
|------|------------|
| Login downtime during hydra/auth recreate | Off-peak; apply hydra → auth in sequence; keep admin URI on stable host |
| OpenTofu state force-new surprises | `tofu plan` per app before apply; watch destroy count |
| Domain mapping cert stuck | Grey DNS for ACME; wait up to 24h; check Google docs CDN note |
| Preview domain mapping latency | Monitor; LB remains break-glass |
| Service repos still ship to west9 | Update all cloudrun-ship `region` inputs |
| Scheduler in europe-west1 already | Targets must use new run URLs / stable hosts |

---

## 9. Success criteria

- All production Cloud Run in **`europe-west1` only**  
- `oauth2*`, `authz*`, `accounts` on **domain mappings** (or documented interim CF)  
- `api.stawi.org` Worker only for **path** APIs  
- No Google Global LB required for identity hosts  
- Login + token + keto S2S green  
