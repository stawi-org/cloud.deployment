# finance-stawi

Fintech **stawi** product service (group lending) from
`antinvestor/service-fintech/apps/stawi`.

| Layer | Value |
|-------|--------|
| GCP | `finance` / `stawi-finance` |
| Neon | `finance` org |
| Image | `ghcr.io/antinvestor/service-fintech-stawi` |
| Edge path | `https://api.stawi.org/stawi` |
| Hydra client | `service-stawi` |

Peers (all via api.stawi.org): identity, loans, savings, ledger, payment,
notification, files, profile, tenancy, limits, audit, trustage. The setup job
syncs `/workflows/*.json` into trustage and registers the permission manifest.

Ship: `service-fintech` tag → `cloudrun-ship` job `ship-finance-stawi`.
