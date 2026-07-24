# platform-files

Platform-domain Cloud Run app (service-files apps/default).

| Layer | Value |
|-------|--------|
| GCP | `platform` / `stawi-platform` |
| Neon | `identity` org (interim) until platform Neon account is ready |
| Image | `ghcr.io/antinvestor/service-files:v1.10.54` (bootstrap; ship via service-repo release) |

Auth depends on identity Hydra + Keto in `stawi-identity`.
