image                    = "ghcr.io/antinvestor/service-trustage:v0.4.8"
container_port           = 8080
resource_path            = "/trustage"
memory                   = "768Mi"
has_database             = true
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
requested_audience_paths = ["/profile", "/tenancy"]
public_hostname = ""  # product surface: api.stawi.org/<path> only

# Supabase migration phase 1: provision project + staging secrets (cutover separate)
supabase_enabled = true
database_cutover = true
# Neon decommission (2026-09-01): project destroyed after Supabase cutover
neon_enabled = false
