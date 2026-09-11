# finance-seed

Fintech **seed** direct-to-client lending service from
`antinvestor/service-fintech/apps/seed`.

| Layer | Value |
|-------|--------|
| GCP | `finance` / `stawi-finance` |
| Neon | `finance` org |
| Image | `ghcr.io/antinvestor/service-fintech-seed` |
| Edge path | `https://api.stawi.org/seed` |
| Hydra client | `service-seed` |

Peers: identity, loans, operations, tenancy, audit. Setup job migrates schema,
seeds the default credit-tier ladder and registers permissions.

Ship: `service-fintech` tag → `cloudrun-ship` job `ship-finance-seed`.
