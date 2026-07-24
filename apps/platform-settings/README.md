# platform-settings

Platform-domain Cloud Run app (service-profile apps/settings).

| Layer | Value |
|-------|--------|
| GCP | `platform` / `stawi-platform` |
| Neon | `identity` org (interim) until platform Neon account is ready |
| Image | `ghcr.io/antinvestor/service-profile-settings:v1.53.5` (bootstrap; ship via service-repo release) |

Auth depends on identity Hydra + Keto in `stawi-identity`.
