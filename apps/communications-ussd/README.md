# communications-ussd

The USSD engine of service-notification (`apps/ussd`), served at
`https://api.stawi.org/ussd`.

- `POST /ussd/gateway/{serviceID}` — telco callbacks. Each service is
  configured with an `auth_key` (Africa's Talking: `?authKey=` in the callback
  URL) and optionally `whitelist_ip`.
- `/api/v1/...` — management API, internal service accounts only.

Runs as `service-notification-ussd` (tenancy migration
`20261026_service_notification_ussd.sql`): `profile_view` on service_profile
to resolve callers, `notification_send` on service_notification to hand over
completed sessions. Setup job: `gcloud run jobs execute communications-ussd-migrate`.
