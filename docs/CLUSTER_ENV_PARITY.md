# Cluster → Cloud Run environment parity

Audit of Colony HelmRelease env (deployment.manifests) against
`modules/frame-cloudrun-app` + per-app `app_env` / secrets.

## Translation rules

| Cluster | Cloud Run |
|---------|-----------|
| `http://service-*.*.svc` | Product: `https://api.stawi.org/<path>`; Hydra: `oauth2*.stawi.org`; Keto: `authz*.stawi.org` |
| `nats://…` `EVENTS_QUEUE_URL` | `gcppubsub://` + dual-URL Frame push (module/pubsub) |
| `NATS_CREDENTIALS_FILE` / SPIFFE / `K8S_*` | Omitted (not applicable) |
| `DATABASE_USERNAME` / `PASSWORD` | Single `DATABASE_URL` Secret Manager |
| `PERMISSIONS_REGISTRATION_URL` | Prefer bulk **setup plan** (`setup.Registry` / Job argv `setup migrate permissions …`). Abstract API: Frame package `setup` (`Step`, `Registry.Run`). Runtime PreStart optional via `PERMISSIONS_REGISTER_ON_START` (default true for Colony). Prod URL: `https://api.stawi.org/tenancy/_internal/register/permissions` |
| `redis://valkey.datastore.svc` | `mem://` or omit until Memorystore |
| OAuth2 / audiences / private_key_jwt | Injected by `frame_oauth_env` (Colony chart parity) |

## Per-app status (stawi-prod)

### Identity

| App | Cluster-specific envs transferred |
|-----|-----------------------------------|
| **identity-authentication** | Service URIs (profile/tenancy/devices/files), FedCM/Hydra public DNS, Google callback+scopes, default tenant/partition, CSRF/cookies, CACHE_URI=mem, EXPOSE_ERRORS |
| **identity-tenancy** | `SYNCHRONISE_PRIMARY_PARTITIONS`, `PROFILE_SERVICE_URI`, `DATABASE_LOG_QUERIES`; **no** self `PERMISSIONS_REGISTRATION_URL` |
| **identity-identity** | Profile/tenancy DNS URIs, notification api path, workload paths, max agent depth |
| **identity-profile** | DEK secrets, notification URI, TRACE_REQUESTS |
| **identity-oauth2-hydra** | Dedicated Hydra stack (not frame module) — CORS, hooks, DSN |
| **identity-authorization-keto** | Dedicated Keto stack — DSN, namespaces (read/write services) |

### Platform

| App | Notes |
|-----|--------|
| **platform-devices** | TURN_PROVIDER/TTL/URLs, analysis queue → Pub/Sub; Cloudflare TURN secrets always mounted |
| **platform-files** | STORAGE_PROVIDER, S3/GCS/local bucket names; S3 credentials always mounted |
| **platform-geolocation / settings** | Frame defaults + permissions registration |

### Operations

| App | Notes |
|-----|--------|
| **operations-audit** | `AUDIT_SIGNING_KEY`, `DATABASE_LOG_QUERIES` — requires Neon `DATABASE_URL` + full frame env (broken if shell-only deploy) |
| **operations-formstore** | MAX_SUBMISSION_SIZE, SUBMISSION_RATE_LIMIT, FILE_SERVICE_URL → `api.stawi.org/files` |
| **operations-queuestore** | ENQUEUE_RATE_LIMIT, STATS_CACHE_TTL_SECONDS |
| **operations-redirect** | JOBS_BASE_URL, LINK_EXPIRED_WEBHOOKS (empty until opportunities migrates), analytics always mounted |
| **operations-thesa** | ANALYTICS_BACKEND_TYPE; analytics URL/token always mounted |
| **operations-trustage** | Full queue dual-URL map + batch/retention knobs from colony |

## Operator secrets (never in git — repo stays public)

### Preferred: cluster → GCP Secret Manager

Vault/OpenBao is the cluster source of truth via ExternalSecrets
(`ClusterSecretStore vault-backend`, KV v2 mount `secret`). Path convention:

| Domain | Vault path prefix |
|--------|-------------------|
| Identity | `stawi/identity/...` |
| Platform | `stawi/platform/...` |
| Operations | `stawi/operations/...` |
| Shared analytics | `stawi/product-opportunities/common/...` |

Canonical Vault access skill (when OpenBao is healthy):

1. `SA_TOKEN=$(kubectl create token external-secrets -n external-secrets --audience=vault --duration=600s)`
2. Find OpenBao leader: `kubectl exec -n vault-system vault-openbao-N -- bao status`
3. Login: `bao write -field=token auth/kubernetes/login role=external-secrets jwt=$SA_TOKEN`
4. Read: `bao kv get -mount=secret stawi/identity/authentication/service-secrets`

When Vault is down (pods Pending / ClusterSecretStore InvalidProviderConfig), ESO
cannot refresh but **materialised k8s Secrets** still hold last-synced values.
Sync those into GCP SM with:

```bash
# Requires kubectl (stawi context) + gcloud secretmanager.admin
./scripts/sync-cluster-secrets-to-gcp.sh
# Optional: ./scripts/sync-cluster-secrets-to-gcp.sh --dry-run
# Optional: ./scripts/sync-cluster-secrets-to-gcp.sh --only identity-authentication-google-oauth-client-id
```

This copies Vault-originated material (Google OAuth, CSRF/cookies, DEK, TURN,
R2/S3, hydra PSK, audit signing key, analytics, …) into project SM **without
writing values into the repository**.

Catalogs (metadata only — ids, env keys, vault path hints):

- `config/secret-catalog/identity.yaml`
- `config/secret-catalog/platform.yaml`
- `config/secret-catalog/operations.yaml`

### Vault → k8s → SM mapping (operator secrets)

| SM secret id | k8s source | Vault remoteRef (when healthy) |
|--------------|------------|--------------------------------|
| `identity-authentication-google-oauth-client-id` | `identity/google-oauth-credentials:client-id` | `stawi/identity/authentication/service-secrets#google_client_id` |
| `identity-authentication-google-oauth-client-secret` | `…:client-secret` | `…#google_secret` |
| `identity-authentication-csrf-secret` | `identity/service-authentication-secrets:csrf-secret` | `…#csrf_secret` |
| `identity-authentication-cookie-hash-key` | `…:secure-cookie-hash-key` | `…#cookie_hash_key` |
| `identity-authentication-cookie-block-key` | `…:secure-cookie-block-key` | `…#cookie_block_key` |
| `identity-oauth2-hydra-secrets-system` | `identity/service-authentication-oauth2-hydra:secretsSystem` | `stawi/identity/oauth2/hydra-secrets#secretsSystem` |
| `identity-oauth2-hydra-secrets-cookie` | `…:secretsCookie` | `…#secretsCookie` |
| `identity-profile-dek-*` | `identity/service-profile-dek` | `stawi/identity/default/dek-keys` |
| `hydra-webhook-psk` | `*/hydra-webhook-psk:psk` | generator / `stawi/identity/authentication/webhook-psk` |
| `platform-files-encryption-phrase` | `platform/service-files-encryption` | ESO generator |
| `platform-files-s3-*` | `platform/cloudflare-r2-storage-creds` | `stawi/platform/files/r2-credentials` |
| `platform-devices-cloudflare-turn-*` | `platform/service-devices-cloudflare-turn-secret` | `stawi/platform/devices/cloudflare-turn` |
| `audit-signing-key` | `operations/audit-signing-key:private_key` | `stawi/operations/audit/signing#private_key` |
| `operations-redirect-analytics-*` | `operations/analytics-credentials-redirect` | `stawi/product-opportunities/common/analytics-credentials` |
| `operations-thesa-analytics-*` | `operations/analytics-credentials-thesa` | `stawi/operations/thesa/analytics` |
| `service-files-encryption` | `operations/service-files-encryption` | ESO generator |

### Alternatives

| Method | Use when |
|--------|----------|
| `scripts/seed-gcp-secrets.sh --from-env-file …` | Operator has a local KEY=value file (chmod 600) |
| `TF_VAR_*` at apply | One-off bootstrap; prefer sync script |
| Generate random | Hydra secrets already generated in cluster / tofu |

### Env parity audit (no secret values)

```bash
./scripts/audit-env-parity.sh
./scripts/audit-env-parity.sh --catalog-only   # SM versions only
./scripts/audit-env-parity.sh --json
```

Compares Colony HelmRelease `values.env` + oauth2 chart settings to live Cloud Run,
and verifies required catalog secret IDs have enabled SM versions.

## Public repository guarantees

| In git (OK) | Never in git |
|-------------|--------------|
| Secret **IDs** and env **key names** | Secret **values** |
| Vault **path hints** (metadata) | `.env` files with credentials |
| Terraform `extra_secret_ids` | `TF_VAR_*` committed |
| SOPS-encrypted `credentials/**` | Age keys / plaintext API keys |
| Scripts that **read** cluster/SM at runtime | Sync script stdout redirected into repo |

## Intentionally not copied

- Cluster NATS JetStream URL shapes (replaced by Pub/Sub)
- SPIFFE workload API sockets
- Valkey internal DNS (no Memorystore yet)
- Product-opportunities in-cluster webhooks (empty until those apps migrate)
- GHCR pull secrets (images are public)
- CNPG `db-credentials-*` (Neon `DATABASE_URL` instead)
