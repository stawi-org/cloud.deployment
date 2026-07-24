# cloud.deployment

Modular **Cloud Run + Neon** deployments for Stawi edge/greenfield applications.

## Boundaries

| Repo | Owns |
|------|------|
| [`deployment.infra`](https://github.com/stawi-org/deployment.infra) | Cluster foundation (Talos, nodes, Flux bootstrap, DNS foundation) |
| [`deployment.manifests`](https://github.com/stawi-org/deployment.manifests) | **All** Kubernetes deployments (Colony, Gateway, CNPG, NATS, Flux) |
| **This repo** | OpenTofu modules + per-app Cloud Run/Neon stacks + path-filtered CI |
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

## Status

Architecture accepted. Implementation follows the PR plan in the design doc.
