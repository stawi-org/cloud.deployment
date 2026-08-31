# Supabase migration: trustage, audit, keto, hydra

Date: 2026-08-31
Status: draft — pending user approval
Scope: migrate the databases of four apps from Neon to Supabase, in this
order: `operations-trustage` → `operations-audit` →
`identity-authorization-keto` → `identity-oauth2-hydra`. All other apps
stay on Neon; both providers coexist indefinitely.

## Why these four / order

Highest-query apps chosen by the user. Trustage first (lowest blast
radius of the four), audit second, then the auth spine last — keto, and
finally hydra (token issuance; any mistake is platform-wide).

## Current state (per app)

Each app has its own Neon project (default database, owner role). Two
Secret Manager secrets carry connection URIs:
- `<app>-database-url` — pooled (runtime `DATABASE_URL` + `REPLICA_DATABASE_URL`)
- `<app>-database-url-direct` — direct (migrate job; also keto's runtime,
  because transaction pooling breaks pgx prepared statements, SQLSTATE 26000)

trustage + audit wire through `modules/frame-cloudrun-app`; keto + hydra
instantiate `modules/neon-database` directly in their root modules.
TimescaleDB was removed platform-wide on 2026-08-31; extensions in use
are the base five (`uuid-ossp`, `pg_stat_statements`, `pg_trgm`,
`btree_gin`, `btree_gist`) for trustage/audit and none for keto/hydra.

## Design

### Supabase layout

- One Supabase **organization per domain**, mirroring Neon accounts:
  `operations` (trustage, audit) and `identity` (keto, hydra) — subject
  to user confirmation. One **project per app**, project name = app name,
  region `eu-central-1` (Frankfurt; matches Neon `aws-eu-central-1`).
- Paid plan required: free projects pause after ~1 week of inactivity
  and cap connections — not acceptable for the auth spine.

### Connection URL mapping (the load-bearing part)

Supabase's direct endpoint (`db.<ref>.supabase.co`) is IPv6-only without
a paid add-on, and Cloud Run egress is IPv4 — so both URLs use the
Supavisor pooler host, different ports/modes:

| Secret | Neon (today) | Supabase (after) |
|---|---|---|
| `<app>-database-url` | PgBouncer pooled URI | pooler **transaction** mode, port 6543 |
| `<app>-database-url-direct` | direct URI | pooler **session** mode, port 5432 |

Session mode preserves the two properties "direct" is load-bearing for:
migrate jobs' session advisory locks, and keto's prepared statements.
`sslmode=require` is set explicitly in both URLs (Neon URIs embedded it;
constructed Supabase URLs must add it).

### Terraform

- New `modules/supabase-database`: provider `supabase/supabase ~> 1.0`;
  `supabase_project` (org slug, name, generated `random_password`,
  region, `instance_size`); reads `supabase_pooler` data source and
  constructs the two URLs; optional psql `local-exec` extension
  provisioner identical in shape to the Neon module's. Output contract
  matches `modules/neon-database`: `connection_uri` (session),
  `pooled_connection_uri` (transaction).
- `modules/frame-cloudrun-app` does NOT instantiate the Supabase module
  (that would force the supabase provider on every app root, count=0 or
  not). Instead it gains optional sensitive overrides
  `database_url_override` / `database_url_direct_override` (default
  null): when set, the two live secrets carry those values instead of
  the Neon module outputs; the Neon project keeps existing either way
  (rollback = unset). trustage/audit instantiate
  `modules/supabase-database` in their own roots and pass the overrides
  behind a `database_cutover` tfvars bool. keto/hydra wire the module
  next to their existing neon-database call and switch their secret
  values the same way.
- Neon module, provider, and all other apps: untouched.

### Credentials / CI

Mirror the Neon chain exactly:
- `config/supabase-accounts.yaml` (org slug per account, allowed
  prefixes/envs) + SOPS `credentials/supabase/<account>/auth.yaml`
  holding the access token (`.sops.yaml` rule added).
- `resolve-app-context.sh` reads `app.yaml`'s `supabase.account`;
  `load-sops-credentials.sh` exports `TF_VAR_supabase_access_token` /
  `TF_VAR_supabase_org_id`; `app-tofu.yml` passes them through.
- App root modules gain a `supabase` provider block behind the same
  variables (dummy value in validate, like Neon's).

### Two-phase cutover per app (order: trustage, audit, keto, hydra)

Phase 1 — provision: set `database_provider = "supabase"` **plus**
`database_cutover = false` in tfvars. Terraform creates the Supabase
project and writes the two URLs into NEW secrets
(`<app>-supabase-database-url[-direct]`) but leaves the live secrets on
Neon values. No service impact.

Phase 2 — cutover: run the data copy (below), then set
`database_cutover = true`; apply repoints the two live secrets to the
Supabase URLs and rolls a new Cloud Run revision + migrate job. Neon
project left intact (rollback = flip the flag back) until a later
decommission PR.

### Data copy (brief write pause approved)

Per app, during a low-traffic window:
1. Scale service to min instances 0 / hold writes (~minutes).
2. `pg_dump --no-owner --no-privileges` from the Neon direct URI;
   restore via psql to the Supabase session-mode URL (objects land under
   the `postgres` role; app connects as `postgres.<ref>` via pooler).
3. Verify row counts per table; run the app's migrate job against
   Supabase (should no-op); flip cutover flag, apply, smoke-test.

App-specific cautions:
- **hydra**: JWKs are AEAD-encrypted under `SECRETS_SYSTEM` — copy rows
  verbatim, never rotate that secret during the move; token/consent
  tables must land complete or sessions die. Do hydra last, alone.
- **keto**: relation-tuple tables are the authorization source of truth;
  verify counts exactly; runtime stays on session mode.
- **audit/trustage**: append-only; smallest risk (audit currently ~0 rows).

### Explicitly out of scope

- The other 8+ database apps (stay on Neon).
- Neon decommission of migrated projects (separate later PR).
- Supabase Auth/Storage/Realtime — Postgres only.

## Open questions (block provisioning)

1. Supabase org layout + billing: two paid orgs (operations, identity)
   as designed, or a single org? Which plan/instance size?
2. Bootstrap: someone must create the org(s) in the Supabase dashboard
   and generate a personal access token; the token gets SOPS-encrypted
   into `credentials/supabase/…`. Needs the user (dashboard + age key).
