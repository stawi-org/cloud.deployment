#!/usr/bin/env bash
# Operator helper for Cloud Run public edge domain mappings.
#
# Usage:
#   ./scripts/setup-public-edge-domains.sh status
#   ./scripts/setup-public-edge-domains.sh verify-hint
#   ./scripts/setup-public-edge-domains.sh enable-tfvars   # sets enable_domain_mapping=true
#   ./scripts/setup-public-edge-domains.sh describe
#
# Domain mapping requires prior verification:
#   gcloud domains verify stawi.org
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${REGION:-europe-west9}"
PROJECT_IDENTITY="${PROJECT_IDENTITY:-stawi-identity}"

cmd="${1:-status}"

verified() {
  gcloud domains list-user-verified --format='value(id)' 2>/dev/null | grep -E 'stawi\.org' || true
}

case "$cmd" in
  status)
    echo "=== Google verified domains (current user) ==="
    gcloud domains list-user-verified 2>&1 || true
    echo
    echo "=== Domain mappings (identity) ==="
    gcloud beta run domain-mappings list --project="$PROJECT_IDENTITY" --region="$REGION" 2>&1 || true
    echo
    echo "=== Cloud Run services ==="
    gcloud run services list --project="$PROJECT_IDENTITY" --region="$REGION" \
      --format='table(metadata.name,status.url)' 2>&1 || true
    gcloud run services list --project=stawi-platform --region="$REGION" \
      --format='table(metadata.name,status.url)' 2>&1 || true
    echo
    echo "=== tfvars domain flags ==="
    for f in \
      apps/identity-authentication/cloudrun/envs/stawi-prod.tfvars \
      apps/identity-oauth2-hydra/cloudrun/envs/stawi-prod.tfvars \
      apps/edge-api/cloudrun/envs/stawi-prod.tfvars; do
      echo "--- $f ---"
      grep -E 'public_hostname|enable_domain|advertise_public' "$ROOT/$f" 2>/dev/null || true
    done
    ;;
  verify-hint)
    cat <<'EOF'
1) Verify domain ownership (interactive browser / DNS TXT):
     gcloud domains verify stawi.org

2) Confirm:
     gcloud domains list-user-verified

3) Enable mappings in tfvars:
     ./scripts/setup-public-edge-domains.sh enable-tfvars
     git commit && push  →  app-apply creates mappings

4) Add Cloudflare DNS records from:
     gcloud beta run domain-mappings describe --domain=oauth2.stawi.org \
       --region=europe-west9 --project=stawi-identity

   Prefer DNS-only (grey cloud) until certificate Active.

5) After oauth2 cutover:
     set advertise_public_hostname = true on identity-oauth2-hydra
     re-apply hydra

See docs/PUBLIC_EDGE_DNS.md for full sequence.
EOF
    ;;
  enable-tfvars)
    if [[ -z "$(verified)" ]]; then
      echo "WARNING: stawi.org not in gcloud domains list-user-verified."
      echo "Mapping apply will fail until you run: gcloud domains verify stawi.org"
      echo "Proceeding to flip tfvars anyway (you asked to enable)."
    fi
    for f in \
      "$ROOT/apps/identity-authentication/cloudrun/envs/stawi-prod.tfvars" \
      "$ROOT/apps/identity-oauth2-hydra/cloudrun/envs/stawi-prod.tfvars" \
      "$ROOT/apps/edge-api/cloudrun/envs/stawi-prod.tfvars"; do
      if grep -q 'enable_domain_mapping' "$f"; then
        sed -i 's/enable_domain_mapping\s*=\s*false/enable_domain_mapping     = true/' "$f" || \
        sed -i 's/enable_domain_mapping = false/enable_domain_mapping = true/' "$f"
      fi
      echo "updated $f"
      grep enable_domain_mapping "$f" || true
    done
    echo "Commit and apply authentication, hydra, edge-api."
    ;;
  describe)
    for d in accounts.stawi.org oauth2.stawi.org api.stawi.org; do
      echo "=== $d ==="
      gcloud beta run domain-mappings describe --domain="$d" \
        --region="$REGION" --project="$PROJECT_IDENTITY" 2>&1 || echo "(not mapped)"
      echo
    done
    ;;
  *)
    echo "Usage: $0 {status|verify-hint|enable-tfvars|describe}" >&2
    exit 2
    ;;
esac
