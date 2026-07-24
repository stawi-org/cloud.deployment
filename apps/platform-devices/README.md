# platform-devices

Platform-domain Cloud Run app (service-profile apps/devices).

| Layer | Value |
|-------|--------|
| GCP | `platform` / `stawi-platform` |
| Neon | `identity` org (interim) until platform Neon account is ready |
| Image | `ghcr.io/antinvestor/service-profile-devices:v1.53.5` (bootstrap; ship via service-repo release) |

Auth depends on identity Hydra + Keto in `stawi-identity`.
