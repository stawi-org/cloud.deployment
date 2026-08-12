# platform-calendar

Product-agnostic **resource booking** service (`service_calendar`).
Source binary: `stawi-opportunities/opportunities` `apps/calendar`.

| Layer | Value |
|-------|--------|
| GCP | `platform` / `stawi-platform` (europe-west1) |
| Neon | `platform` → `org-calm-cell-68997035` |
| Image | `ghcr.io/stawi-opportunities/opportunities-calendar` |
| Edge path | `https://api.stawi.org/calendar` |
| Audience | `/calendar` (`service_calendar`) |
| Hydra SA | `service-calendar` (derived from `platform-*`) |
| Auth | Identity Hydra/Keto in `stawi-identity` |

Do **not** deploy this under `opportunities-*`. Calendar is a shared platform
plane (people, rooms, equipment). Product ATS is a consumer via
`CALENDAR_SERVICE_URI=https://api.stawi.org/calendar`.

## Consumers

- **opportunities-ats** — interview availability, slot list, booking
  (`CALENDAR_SERVICE_URI`, `CALENDAR_SERVICE_DIRECT` unset in prod)

## Ship

```text
opportunities tag v8.1.0+
  → docker-release builds ghcr.io/stawi-opportunities/opportunities-calendar:vX.Y.Z
  → pin cloudrun/envs/stawi-prod.tfvars (first apply) then app-apply
```

```bash
gh workflow run app-apply.yml -f app=platform-calendar -f env=stawi-prod
```

Setup Job migrates schema and registers `service_calendar` permissions.
Runtime does not migrate. Requires `hydra-webhook-psk` (shared with other
platform apps) and a Hydra SA client `service-calendar`.
