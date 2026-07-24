# Neon Multi-Account Secret Storage Design

**Date:** 2026-07-24  
**Status:** Accepted  
**Repo:** [stawi-org/cloud.deployment](https://github.com/stawi-org/cloud.deployment)

## Problem

Cloud Run apps each get **one Neon project**, but those projects must live under **different Neon organizations (accounts)** so that:

| Domain | Example apps | Why separate Neon org |
|--------|--------------|------------------------|
| **Identity** | auth edge, profile, tenancy helpers | Highest sensitivity; compromise must not touch money or messaging data |
| **Notifications** | email/SMS workers, preference services | High volume, different retention; blast isolation from identity |
| **Payments** | checkout, ledger-facing edges | Compliance / card-adjacent; strictest access and audit |
| **Labs / experimental** | prototypes, sandboxes | No path to prod customer data |

Today we only had two generic keys (`stawi-org`, `stawi-labs`) and CI loaded **all** GitHub Neon secrets into a single step to pick one. That fails as account count grows:

1. **No domain model** — operators cannot see which org owns identity vs payments.
2. **Secret co-location in CI** — every declared Neon key is available to the job step even when only one is needed (GitHub cannot dynamically index `secrets[name]`).
3. **No access policy** — any app could set `neon.account: payments` with no guardrails.
4. **No rotation / ownership** — unclear who rotates which key, or where the canonical copy lives.
5. **Local vs CI** — no rule for who may hold which key on a laptop.

This document defines a thorough model for **registry + secure storage + least-privilege injection + governance**.

---

## Goals

1. **Domain-separated Neon orgs** (identity / notifications / payments / labs at minimum).
2. **Secrets never in git**; only non-secret metadata in the repo.
3. **Least privilege in CI:** a job for app A only ever obtains the Neon API key for A’s declared account.
4. **Scalable registration:** adding a domain is registry + secret store entry, not a redesign.
5. **Auditable ownership and rotation.**
6. **Compatible** with per-app OpenTofu roots, multi-account Neon provider pattern, and R2 state isolation.
7. **Fits existing Stawi tooling:** GitHub Actions, optional Vault/OpenBao (already on cluster), age/SOPS patterns from `deployment.infra`.

## Non-goals

- Storing **runtime** DB passwords here (those go to GCP Secret Manager per app, already).
- Neon Auth product configuration (app-level).
- Migrating cluster CNPG databases into Neon.
- Replacing cluster Vault for Kubernetes ExternalSecrets.

---

## Concepts

```
Neon Organization (billing + members + API keys)
  └── Neon Project (one per app — already our module contract)
        └── branches / databases / roles
```

| Term | Meaning in this design |
|------|------------------------|
| **Neon account** | A Neon **Organization** we treat as a security and billing boundary |
| **Account key** | Short stable id in git (`identity`, `payments`, …) |
| **API key** | Neon org API key used by OpenTofu `provider "neon"` at plan/apply time only |
| **Registry** | `config/neon-accounts.yaml` — public metadata, no secrets |
| **Secret material** | The API key string — only in approved secret stores |

**Rule:** One OpenTofu apply uses **exactly one** Neon API key (the app’s `neon.account`). Never configure multiple Neon providers with live keys in the same root for “convenience.”

---

## Recommended Neon org topology

Create **separate Neon organizations** (not only separate projects under one org):

| Account key | Neon org (suggested name) | Intended workloads | Sensitivity |
|-------------|---------------------------|--------------------|-------------|
| `identity` | Stawi Identity | Identity/auth/profile-related Cloud Run apps | Critical |
| `notifications` | Stawi Notifications | Notification pipelines, templates, delivery workers | High |
| `payments` | Stawi Payments | Payment/checkout/ledger-adjacent edge apps | Critical + compliance |
| `platform` | Stawi Platform Edge | Shared non-sensitive platform edges (if any) | Medium |
| `labs` | Stawi Labs | Experiments, throwaway projects | Low |

### Why org-level, not “many projects one org”

| Approach | Pros | Cons |
|----------|------|------|
| **Separate orgs (chosen)** | Separate API keys, membership, billing, and console access; compromise of notifications key cannot list/delete identity projects | More Neon orgs to manage |
| One org, many projects | Simpler billing | One org API key is god-mode over all projects; membership is shared |
| One org + fine-grained keys | Ideal if Neon offers project-scoped deploy keys | Must re-evaluate when Neon product supports; today design assumes **org API keys** |

If Neon later provides **project-scoped** or **role-scoped** keys, prefer those **inside** each domain org; do not collapse domain orgs without an ADR.

### Environment split (optional hardening)

For payments (and optionally identity):

| Pattern | When |
|---------|------|
| **Same org, separate projects** per env (`app` + `stawi-dev` / `stawi-prod` in project name) | Default for most domains |
| **Separate Neon orgs** `payments-dev` / `payments-prod` | When compliance requires full isolation of prod API credentials |

Registry supports both: account keys `payments-dev` and `payments-prod`, apps pin by env via `app.yaml` or env-specific overlay (see App binding).

---

## Architecture: three layers

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer A — Registry (git, non-secret)                            │
│  config/neon-accounts.yaml                                       │
│  account key → github_environment, vault_path, owners, policy    │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│  Layer B — Secret material (never git)                           │
│  Primary (CI least-privilege): GitHub Environment secrets        │
│  Canonical / break-glass / human: Vault (OpenBao) paths          │
│  Optional: GCP Secret Manager for operator tooling only          │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│  Layer C — Injection (CI / local)                                │
│  Resolve app.yaml neon.account → fetch ONE key → TF_VAR_neon_api_key │
│  OpenTofu provider "neon" { api_key = var.neon_api_key }         │
└─────────────────────────────────────────────────────────────────┘
```

### Layer A — Registry (`config/neon-accounts.yaml`)

Public, reviewed in PRs. Example shape:

```yaml
# No secrets in this file.
version: 1
accounts:
  identity:
    description: Identity domain Neon organization
    owners: [identity-team]
    # GitHub Actions Environment name (must exist; holds secret NEON_API_KEY)
    github_environment: neon-identity
    # Canonical Vault/OpenBao path (kv-v2 path without mount prefix conventions documented below)
    vault_path: cloud-deployment/neon/identity
    # Human-readable Neon org id/slug for operators (optional)
    neon_org_hint: "Stawi Identity"
    # Policy: which deploy envs may use this account
    allowed_deploy_envs: [stawi-dev, stawi-prod]
    # Optional: app name prefixes allowed to select this account (empty = any after human review)
    allowed_app_prefixes: []
    sensitivity: critical

  notifications:
    description: Notifications domain Neon organization
    owners: [communications-team]
    github_environment: neon-notifications
    vault_path: cloud-deployment/neon/notifications
    neon_org_hint: "Stawi Notifications"
    allowed_deploy_envs: [stawi-dev, stawi-prod]
    allowed_app_prefixes: []
    sensitivity: high

  payments:
    description: Payments domain Neon organization
    owners: [finance-team]
    github_environment: neon-payments
    vault_path: cloud-deployment/neon/payments
    neon_org_hint: "Stawi Payments"
    allowed_deploy_envs: [stawi-dev, stawi-prod]
    allowed_app_prefixes: [payment-, checkout-, billing-, ledger-]
    sensitivity: critical

  labs:
    description: Experimental / non-production Neon organization
    owners: [platform]
    github_environment: neon-labs
    vault_path: cloud-deployment/neon/labs
    neon_org_hint: "Stawi Labs"
    allowed_deploy_envs: [stawi-dev]   # labs must not deploy to prod
    allowed_app_prefixes: []
    sensitivity: low
```

**Validation (CI):**

- Every `apps/*/app.yaml` `neon.account` ∈ registry keys (except `_template` may use a placeholder).
- App’s selected deploy env ∈ `allowed_deploy_envs`.
- If `allowed_app_prefixes` non-empty, app name must match one prefix.
- `github_environment` and `vault_path` required for production accounts.

### Layer B — Where secret material lives

#### B1. GitHub Environment secrets (**primary for Actions least privilege**)

GitHub cannot dynamically index `secrets['NEON_API_KEY_' + account]` safely without putting every secret into the job. **Environments fix this:**

| GitHub Environment | Secret name (always the same) | Holds |
|--------------------|-------------------------------|--------|
| `neon-identity` | `NEON_API_KEY` | Identity org API key |
| `neon-notifications` | `NEON_API_KEY` | Notifications org API key |
| `neon-payments` | `NEON_API_KEY` | Payments org API key |
| `neon-labs` | `NEON_API_KEY` | Labs org API key |

Job:

```yaml
environment: ${{ needs.meta.outputs.github_environment }}  # e.g. neon-payments
# Only that environment's secrets are available → single NEON_API_KEY
```

**Benefits:**

- Adding a domain does **not** require editing every workflow `secrets:` block with a new global secret name.
- Payments apply jobs never see the identity key.
- Environment protection rules: required reviewers for `neon-payments` apply; wait timers; restricted branches.

**Repo-level secrets to avoid for Neon API keys:** do not store all domain keys as `NEON_API_KEY_IDENTITY`, `NEON_API_KEY_PAYMENTS`, … on the repository and dump them into one step (legacy anti-pattern).

#### B2. Vault / OpenBao (**canonical store + human break-glass**)

Cluster already runs Vault for Kubernetes. Treat Vault as **source of truth** for operators:

```
kv-v2 mount: secret/   (or org standard)
path: secret/data/cloud-deployment/neon/<account_key>
data:
  api_key: "..."
  rotated_at: "2026-07-24"
  neon_org: "Stawi Payments"
```

| Use | How |
|-----|-----|
| Rotate | Update Vault → sync to GitHub Environment (script or human dual-control) |
| Audit | Vault audit log who read/wrote |
| Policies | `identity-team` can write `.../neon/identity` only; CI role read-only |
| Future CI | GHA OIDC → Vault JWT auth → `vault kv get` **only** `vault_path` for this job |

Until OIDC-to-Vault is wired, **GitHub Environment is what CI reads**; Vault is still required for ownership and rotation records.

#### B3. What we explicitly reject for Neon API keys

| Store | Why reject as primary |
|-------|------------------------|
| Plain git / `.env` committed | Leak risk |
| SOPS-encrypted keys in this repo | Tempting (infra does SOPS for GCP auth) but puts decrypt capability on every CI job with age key; broader blast than env secrets; dual-maintenance with Environments |
| Single shared “super” Neon key | Destroys domain isolation |
| Runtime Cloud Run env var for org API key | Org keys are **deploy-time only**; apps use DB URLs from Secret Manager |

SOPS may still encrypt **operator helper files** outside the default CI path (e.g. offline runbooks) if needed—never as the only copy of prod payments keys.

---

## Layer C — Injection flows

### C1. GitHub Actions (plan/apply)

```
detect changed apps
  → for each (app, env):
       read apps/<app>/app.yaml neon.account
       lookup registry → github_environment, policy checks
       job:
         environment: <github_environment>
         secrets: NEON_API_KEY from that environment only
         export TF_VAR_neon_api_key
         tofu plan|apply
```

**Matrix jobs must not share a workspace that already exported another domain’s key.** One job = one app = one environment = one key.

### C2. Local developer

| Account | Local access |
|---------|----------------|
| `labs` | Allowed via personal Neon API key or labs org key in shell env `TF_VAR_neon_api_key` |
| `identity` / `notifications` / `payments` **dev** | Break-glass via Vault read (team policy) or short-lived key; never long-lived on laptops for payments |
| `payments` **prod** | **No** laptop keys by default; CI + dual approval only |

```bash
# labs only example
export TF_VAR_neon_api_key="$(vault kv get -field=api_key secret/cloud-deployment/neon/labs)"
tofu plan -var-file=envs/stawi-dev.tfvars ...
```

### C3. OpenTofu

Unchanged provider pattern:

```hcl
provider "neon" {
  api_key = var.neon_api_key  # sensitive; never written to tfvars in git
}
```

State in R2 holds Neon resource IDs; **API key is not stored in state** if only used in provider config (provider credentials are not state). Connection URIs for DBs remain sensitive in state—already accepted; protect R2 access.

---

## App binding

```yaml
# apps/checkout-edge/app.yaml
name: checkout-edge
owners: [finance-team]
envs: [stawi-dev, stawi-prod]
neon:
  account: payments          # domain account key
runtime: cloudrun
domain: payments             # optional explicit domain label for policy/docs
```

```yaml
# apps/notification-worker/app.yaml
neon:
  account: notifications
```

```yaml
# apps/identity-bff/app.yaml
neon:
  account: identity
```

### Policy enforcement points

1. **PR validate job** — `scripts/validate-neon-accounts.sh` fails on unknown account, forbidden env, prefix mismatch.
2. **Human review** — CODEOWNERS on `apps/payment-*/**` and `config/neon-accounts.yaml`.
3. **GitHub Environment protection** — payments apply requires reviewer.

---

## Threat model (summary)

| Threat | Mitigation |
|--------|------------|
| Leaked GitHub repo contents | No keys in git; registry only |
| Compromised GHA for checkout-edge | Job environment `neon-payments` only → cannot destroy identity Neon projects |
| Compromised GHA for any app with multi-secret dump | Avoided by Environment-scoped single `NEON_API_KEY` |
| Malicious PR sets `neon.account: payments` on random app | Prefix policy + CODEOWNERS + Environment reviewers on apply |
| Stolen laptop with labs key | Labs org has no prod data; prod keys not on laptops |
| Key rotation forgotten | Registry `owners` + quarterly rotation checklist in BACKEND/PILOT |
| Insider with Vault root | Org process; dual control for payments writes; audit log |
| State backend leak | R2 IAM; connection strings in state — separate from org API key blast radius |

---

## Comparison of storage options (decision record)

| Option | Least privilege CI | Ops fit for Stawi | Decision |
|--------|--------------------|-------------------|----------|
| Repo secrets `NEON_API_KEY_*` + env dump | Poor (all keys in step) | Easy but unsafe at scale | **Deprecated** |
| **GitHub Environment per account** | **Strong** | Native GHA, protection rules | **Primary for CI** |
| Vault OIDC fetch per job | Strongest + audit | Needs OIDC role setup | **Phase 2; canonical human store now** |
| SOPS in git | Medium | Matches infra GCP auth pattern | **Not for Neon API keys** |
| GCP Secret Manager | Good with WIF | Good for GCP-native ops | Optional mirror; not required if Vault + GH Env |

---

## Operational procedures

### Add a new Neon domain account

1. Create Neon **Organization**; create API key labeled `cloud-deployment-gha`.
2. Write key to Vault `cloud-deployment/neon/<key>`.
3. Create GitHub Environment `neon-<key>`; add secret `NEON_API_KEY`; set protection rules.
4. PR: add entry to `config/neon-accounts.yaml` (owners, prefixes, allowed envs).
5. CODEOWNERS / team permissions as needed.
6. First app sets `neon.account: <key>`.

### Rotate an API key

1. Create new key in Neon org; do not delete old yet.
2. Update Vault path.
3. Update GitHub Environment secret `NEON_API_KEY`.
4. Re-run plan for one canary app in that domain.
5. Revoke old Neon key.
6. Record `rotated_at` in Vault metadata / team log.

### Revoke after incident

1. Revoke Neon key in console (immediate).
2. Clear GitHub Environment secret; disable Environment if needed.
3. Rotate Vault; investigate Actions run logs (keys should be masked).
4. Re-issue key only after root cause.

---

## Implementation plan (this repo)

| Step | Work |
|------|------|
| 1 | Expand `config/neon-accounts.yaml` to domain accounts + schema docs |
| 2 | Add `.github/scripts/validate-neon-accounts.sh` + validate workflow step |
| 3 | Change `app-tofu` / plan / apply to use **GitHub Environment** from registry (single `NEON_API_KEY`) |
| 4 | Update BACKEND.md, ADDING_AN_APP.md, PILOT_CHECKLIST; deprecate multi-secret dump |
| 5 | Template `app.yaml` documents choosing a domain account |
| 6 | (Later) Vault OIDC step optional behind flag |
| 7 | (Ops) Create Neon orgs + GH Environments + Vault paths offline |

---

## Success criteria

- [ ] Registry lists domain accounts (identity, notifications, payments, labs at minimum).
- [ ] No workflow step receives more than one Neon org API key.
- [ ] Invalid `neon.account` or env/prefix policy fails CI before tofu.
- [ ] Adding payments isolation does not require identity teams to share keys.
- [ ] Docs describe rotation, ownership, and local vs CI access.

---

## Key decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Isolation boundary | Neon **Organization** per domain | Strongest practical key and membership split |
| CI secret delivery | **GitHub Environment** per account, secret name `NEON_API_KEY` | Least privilege despite GHA secret API limits |
| Canonical operator store | **Vault/OpenBao** | Audit, team policies, rotation source of truth |
| App selection | `app.yaml` → `neon.account` | Explicit, reviewable, feeds CI |
| Policy | allowed_deploy_envs + optional prefixes | Prevents labs→prod and casual payments selection |
| Runtime | Never ship org API key to Cloud Run | Deploy-time only; DB URL via Secret Manager |
