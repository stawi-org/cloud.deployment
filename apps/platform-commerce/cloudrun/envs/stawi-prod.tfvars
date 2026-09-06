image                    = "ghcr.io/antinvestor/service-commerce:v0.4.3"
resource_path            = "/commerce"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy", "/checkout", "/ledger", "/notification", "/trustage"]
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
# Where the hosted checkout page returns buyers; shops may override per shop.
checkout_return_url = "https://console.stawi.org/orders/{order_id}"
