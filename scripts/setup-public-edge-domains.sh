#!/usr/bin/env bash
# Status helper for the OpenTofu-managed public edge (HTTPS LB + Cloudflare DNS).
#
# DNS, certs, and host routing are owned by:
#   apps/edge-lb-identity  (stawi-identity)
#   apps/edge-lb-platform  (stawi-platform)
# See docs/PUBLIC_EDGE_DNS.md — do not hand-edit Cloudflare for these hosts.
#
# Usage:
#   ./scripts/setup-public-edge-domains.sh status
#   ./scripts/setup-public-edge-domains.sh apply-hint
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${REGION:-europe-west1}"

IDENTITY_HOSTS=(accounts oauth2 profile tenancy identity)
PLATFORM_HOSTS=(devices settings geolocation files)

cmd="${1:-status}"

case "$cmd" in
  status)
    echo "=== Certificate Manager (identity) ==="
    gcloud certificate-manager certificates describe edge-id-cert \
      --project=stawi-identity --location=global \
      --format='yaml(managed.state,managed.provisioningIssue,managed.authorizationAttemptInfo)' 2>&1 || true
    echo
    echo "=== Certificate Manager (platform) ==="
    gcloud certificate-manager certificates describe edge-pl-cert \
      --project=stawi-platform --location=global \
      --format='yaml(managed.state,managed.provisioningIssue,managed.authorizationAttemptInfo)' 2>&1 || true
    echo
    echo "=== Global LB IPs ==="
    gcloud compute addresses describe edge-id-ip --global --project=stawi-identity \
      --format='value(address)' 2>&1 || true
    gcloud compute addresses describe edge-pl-ip --global --project=stawi-platform \
      --format='value(address)' 2>&1 || true
    echo
    echo "=== Live DNS (public resolvers) ==="
    for h in "${IDENTITY_HOSTS[@]}" "${PLATFORM_HOSTS[@]}"; do
      printf '%-40s ' "${h}.stawi.org"
      dig +short "${h}.stawi.org" A 2>/dev/null | tr '\n' ' ' || true
      echo
    done
    echo
    echo "=== Service public hostname flags (advertise only; mapping stays false) ==="
    for f in \
      apps/identity-oauth2-hydra/cloudrun/envs/stawi-prod.tfvars \
      apps/identity-authentication/cloudrun/envs/stawi-prod.tfvars
    do
      echo "--- $f ---"
      grep -E 'public_hostname|advertise_public' "$ROOT/$f" 2>/dev/null || true
    done
    ;;
  apply-hint)
    cat <<'EOF'
Preferred edge (europe-west1): Cloud Run domain mappings for accounts/oauth2*/authz*.
See docs/REGION_MIGRATION_EUROPE_WEST1.md and scripts/create-domain-mappings.sh.

Break-glass Google LB (edge-lb-identity) only if domain mapping fails:
1) Repo secret CLOUDFLARE_API_TOKEN (Zone:DNS:Edit on stawi.org)
2) gh workflow run app-apply.yml -f app=edge-lb-identity -f env=stawi-prod
3) Wait until Certificate Manager state=ACTIVE

Details: docs/PUBLIC_EDGE_DNS.md docs/SSL_EDGE_POLICY.md
EOF
    ;;
  *)
    echo "Usage: $0 {status|apply-hint}" >&2
    exit 2
    ;;
esac
