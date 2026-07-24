# cloud.deployment

Modular **Cloud Run + Neon + Cloud Pub/Sub** deployments for Stawi edge/greenfield applications.

## Boundaries

| Repo | Owns |
|------|------|
| [`deployment.infra`](https://github.com/stawi-org/deployment.infra) | Cluster foundation (Talos, nodes, Flux bootstrap, DNS foundation) |
| [`deployment.manifests`](https://github.com/stawi-org/deployment.manifests) | **All** Kubernetes deployments (Colony, Gateway, CNPG, NATS, Flux) |
| **This repo** | OpenTofu modules + per-app Cloud Run/Neon/Pub/Sub stacks + path-filtered CI |
| [Colony chart](https://github.com/antinvestor/charts) | Helm chart source used only by `deployment.manifests` |

Kubernetes manifests do **not** live here.

## Design

See [docs/superpowers/specs/2026-07-24-cloud-deployment-architecture-design.md](docs/superpowers/specs/2026-07-24-cloud-deployment-architecture-design.md).

### Highlights

- **App-centric roots:** each app is an independent OpenTofu root with its own R2 state key.
- **Independent CI:** only changed (or module-impacted) apps plan/apply.
- **One Neon project per app**, projects may live under **different Neon accounts**.
- **Public edge only** for talking to cluster platform services (first wave).
- Shared modules mirror the Colony idea: change once, thin app deltas.
- **Messaging is always Cloud Pub/Sub** (cluster NATS is not used from these apps).
- **Neon multi-account:** domain orgs (`identity`, `notifications`, `payments`, …) with least-privilege GitHub Environment secrets — see [docs/BACKEND.md](docs/BACKEND.md) and [the multi-account design](docs/superpowers/specs/2026-07-24-neon-multi-account-secrets-design.md).

## Status

**Scaffold ready for pilot.** Modules (edge-contract, neon-database, cloudrun-service, pubsub), platforms, app template, path-filtered plan/apply CI, and validate guardrails are in place. Next: real GCP project IDs, WIF, and first edge app — see [docs/PILOT_CHECKLIST.md](docs/PILOT_CHECKLIST.md).

## Operator docs

| Doc | Purpose |
|-----|---------|
| [docs/ADDING_AN_APP.md](docs/ADDING_AN_APP.md) | Onboard a new Cloud Run + Neon + Pub/Sub app |
| [docs/MODULES.md](docs/MODULES.md) | Module and platform contracts |
| [docs/BACKEND.md](docs/BACKEND.md) | R2 state, secrets, Neon accounts |
| [docs/PILOT_CHECKLIST.md](docs/PILOT_CHECKLIST.md) | First-app go-live checklist |
