# platform-devices

Platform-domain Cloud Run app.

| Layer | Value |
|-------|--------|
| GCP | `platform` / `stawi-platform` (europe-west1) |
| Neon | `platform` → `org-calm-cell-68997035` (`credentials/neon/platform/auth.yaml`) |
| Neon project | `rough-glade-86902865` |
| Auth | Identity Hydra/Keto in `stawi-identity` |

**Do not** use `neon.account: identity` for this app. See [docs/DEPLOY_PLATFORM.md](../../docs/DEPLOY_PLATFORM.md).
