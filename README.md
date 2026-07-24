# cloud.deployment

Modular **Cloud Run + Neon + Cloud Pub/Sub** deployments.  
**Running an app = choosing GCP + Neon accounts** in `app.yaml`. Secrets live in **GCP Secret Manager**, not git.

## Boundaries

| Repo | Owns |
|------|------|
| [deployment.infra](https://github.com/stawi-org/deployment.infra) | Cluster foundation (Talos, nodes, Flux bootstrap) |
| [deployment.manifests](https://github.com/stawi-org/deployment.manifests) | Kubernetes / Colony / CNPG / NATS |
| **This repo** | Multi-account Cloud Run stacks, Secret Manager, Pub/Sub, path-filtered CI |

## Model

```
app.yaml  →  gcp.account  →  config/gcp-accounts.yaml   →  project / WIF / region
          →  neon.account →  config/neon-accounts.yaml  →  Neon org + SM API key
```

```bash
./.github/scripts/resolve-app-context.sh <app> <env>
```

### Highlights

- **Multi-GCP + multi-Neon** domain accounts (identity, payments, notifications, platform, labs)
- **Secret Manager** for database URLs and other runtime secrets; Neon org keys preferred in SM
- **One OpenTofu root + R2 state per app per env** (independent CI)
- **Pub/Sub only** for messaging (no NATS)
- **Identity greenfield** apps under `apps/identity-*` — [docs/IDENTITY_GREENFIELD.md](docs/IDENTITY_GREENFIELD.md)

## Docs

| Doc | Topic |
|-----|--------|
| [docs/BACKEND.md](docs/BACKEND.md) | Accounts, R2, Secret Manager |
| [docs/ADDING_AN_APP.md](docs/ADDING_AN_APP.md) | Add an app |
| [docs/IDENTITY_GREENFIELD.md](docs/IDENTITY_GREENFIELD.md) | Identity domain big-bang |
| [docs/MODULES.md](docs/MODULES.md) | Modules |
| [docs/superpowers/specs/2026-07-24-multi-account-platform-identity-greenfield.md](docs/superpowers/specs/2026-07-24-multi-account-platform-identity-greenfield.md) | Platform design |
