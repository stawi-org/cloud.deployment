# `identity-profile`

Greenfield identity-domain Cloud Run app.

| Field | Value |
|-------|--------|
| **gcp.account** | `identity` → `config/gcp-accounts.yaml` |
| **neon.account** | `identity` → `config/neon-accounts.yaml` |
| **Runtime secrets** | GCP Secret Manager (e.g. `DATABASE_URL`) |
| **Messaging** | Cloud Pub/Sub |

Deploy context is resolved by:

```bash
./.github/scripts/resolve-app-context.sh identity-profile stawi-dev
```

Do not commit secrets. See `docs/IDENTITY_GREENFIELD.md`.
