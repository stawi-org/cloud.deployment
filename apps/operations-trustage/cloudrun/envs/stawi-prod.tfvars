image           = "ghcr.io/antinvestor/service-trustage:v0.5.1"
container_port  = 8080
resource_path   = "/trustage"
memory          = "768Mi"
has_database    = true
neon_extensions = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
# /commerce: scheduled commerce workflows (reconcile payments, end-of-day ledger)
# /stawi-finance, /stawi-settlement: Stawi process contracts (connect.call to
# finance.v1 / settlement.v1; tenancy grants the trustage client both audiences)
requested_audience_paths = ["/profile", "/tenancy", "/commerce", "/stawi-finance", "/stawi-settlement"]
public_hostname          = "" # product surface: api.stawi.org/<path> only

# Supabase migration phase 1: provision project + staging secrets (cutover separate)
supabase_enabled = true
database_cutover = true
# Neon decommission (2026-09-01): project destroyed after Supabase cutover
neon_enabled = false
