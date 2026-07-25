#!/usr/bin/env bash
# DEPRECATED — classic Cloud Run domain mapping is unavailable in europe-west9 (501).
#
# Public hostnames are served by OpenTofu apps:
#   edge-lb-identity / edge-lb-platform  (modules/cloudrun-host-lb)
# which manage Global HTTPS LB + Certificate Manager + Cloudflare DNS.
#
# See: docs/PUBLIC_EDGE_DNS.md
#      ./scripts/setup-public-edge-domains.sh apply-hint

set -euo pipefail
cat <<'EOF' >&2
ERROR: create-domain-mappings.sh is deprecated.

europe-west9 does not support google_cloud_run_domain_mapping (API 501).

Use OpenTofu instead:
  1. Set GitHub secret CLOUDFLARE_API_TOKEN (Zone:DNS:Edit on stawi.org)
  2. gh workflow run app-apply.yml -f app=edge-lb-identity -f env=stawi-prod
  3. gh workflow run app-apply.yml -f app=edge-lb-platform -f env=stawi-prod

Status: ./scripts/setup-public-edge-domains.sh status
Docs:   docs/PUBLIC_EDGE_DNS.md
EOF
exit 1
