# No container — path-based HTTPS LB + Cloudflare DNS only.
image              = "unused"
cloudflare_zone_id = "706bf604a333d866bb38c03bf643e79a" # stawi.org
cloudflare_proxied = false                              # grey cloud until cert ACTIVE
hostname           = "api.stawi.org"

identity_project_id   = "stawi-identity"
platform_project_id   = "stawi-platform"
operations_project_id = "stawi-operations"
