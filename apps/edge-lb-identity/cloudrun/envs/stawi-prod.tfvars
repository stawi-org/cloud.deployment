# No container — Google HTTPS LB + Cert Manager for control plane only.
# See docs/SSL_EDGE_POLICY.md (oauth2-w, authz, authz-w — always grey-cloud).
image              = "unused"
cloudflare_zone_id = "706bf604a333d866bb38c03bf643e79a" # stawi.org
# cloudflare_proxied forced false in main.tf (control plane)
