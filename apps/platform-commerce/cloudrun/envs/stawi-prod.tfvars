image                    = "ghcr.io/antinvestor/service-commerce:v0.4.3"
resource_path            = "/commerce"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy", "/checkout", "/ledger", "/notification", "/trustage"]
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
# Storefront page buyers are forwarded to after commerce verifies their
# payment at https://api.stawi.org/commerce/payments/return. Empty shows
# commerce's own status page; shops may set their own. (console.stawi.org has
# no DNS record, so pointing here stranded buyers after paying.)
checkout_return_url = ""
