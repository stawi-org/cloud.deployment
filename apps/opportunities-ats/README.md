# opportunities-ats

Employer ATS (`service_ats`). Source: `stawi-opportunities/opportunities` `apps/ats`.

| Layer | Value |
|-------|--------|
| GCP | `opportunities` / `stawi-opportunities` |
| Neon | `opportunities` (own project; not product or crawl) |
| Image | `ghcr.io/stawi-opportunities/opportunities-ats` |
| Edge path | `https://api.stawi.org/ats` |
| Hydra SA | `service-ats` (owns `service_ats`) |
| Calendar | **platform-calendar** at `https://api.stawi.org/calendar` |

```bash
gh workflow run app-apply.yml -f app=opportunities-ats -f env=stawi-prod
```

Apply **after** `platform-calendar` is healthy. ATS will not start without
`CALENDAR_SERVICE_URI`.
