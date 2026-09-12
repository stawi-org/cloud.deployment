# manufacturing

Manufacturing service (`antinvestor/service-manufacturing`, `apps/default`):
recipes, inventory, production planning, batches, equipment, cold chain,
quality, traceability, costing.

| Layer | Value |
|-------|--------|
| GCP | `manufacturing` / `stawi-manufacturing` |
| Neon | `manufacturing` org |
| Image | `ghcr.io/antinvestor/service-manufacturing` |
| Edge path | `https://api.stawi.org/manufacturing` |
| Hydra client | `service-manufacturing` |

Bootstrap once: `bootstrap-gcp-account.sh --account manufacturing --env stawi-prod
--project stawi-manufacturing`, `bootstrap-cloudrun-ship.sh --project stawi-manufacturing
--runtime-sa manufacturing --ship-repo antinvestor/service-manufacturing`,
`bootstrap-neon-account.sh --account manufacturing`.

Ship: `service-manufacturing` tag → `cloudrun-ship` job `ship-manufacturing`.
