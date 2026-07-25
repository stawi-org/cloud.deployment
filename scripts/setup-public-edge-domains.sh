#!/usr/bin/env bash
# Operator helper for per-service Cloud Run domain mappings.
#
# Usage:
#   ./scripts/setup-public-edge-domains.sh status
#   ./scripts/setup-public-edge-domains.sh verify-hint
#   ./scripts/setup-public-edge-domains.sh enable-tfvars
#   ./scripts/setup-public-edge-domains.sh describe
#
# Requires domain verification first:
#   gcloud domains verify stawi.org
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${REGION:-europe-west9}"

# hostname|project|service
HOSTS=(
  "accounts.stawi.org|stawi-identity|identity-authentication"
  "oauth2.stawi.org|stawi-identity|identity-oauth2-hydra"
  "profile.stawi.org|stawi-identity|identity-profile"
  "tenancy.stawi.org|stawi-identity|identity-tenancy"
  "identity.stawi.org|stawi-identity|identity-identity"
  "devices.stawi.org|stawi-platform|platform-devices"
  "settings.stawi.org|stawi-platform|platform-settings"
  "geolocation.stawi.org|stawi-platform|platform-geolocation"
  "files.stawi.org|stawi-platform|platform-files"
)

TFVARS=(
  "apps/identity-authentication/cloudrun/envs/stawi-prod.tfvars"
  "apps/identity-oauth2-hydra/cloudrun/envs/stawi-prod.tfvars"
  "apps/identity-profile/cloudrun/envs/stawi-prod.tfvars"
  "apps/identity-tenancy/cloudrun/envs/stawi-prod.tfvars"
  "apps/identity-identity/cloudrun/envs/stawi-prod.tfvars"
  "apps/platform-devices/cloudrun/envs/stawi-prod.tfvars"
  "apps/platform-settings/cloudrun/envs/stawi-prod.tfvars"
  "apps/platform-geolocation/cloudrun/envs/stawi-prod.tfvars"
  "apps/platform-files/cloudrun/envs/stawi-prod.tfvars"
)

cmd="${1:-status}"

case "$cmd" in
  status)
    echo "=== Google verified domains ==="
    gcloud domains list-user-verified 2>&1 || true
    echo
    for entry in "${HOSTS[@]}"; do
      IFS='|' read -r host project service <<<"$entry"
      echo "=== $host → $project/$service ==="
      gcloud beta run domain-mappings describe --domain="$host" \
        --region="$REGION" --project="$project" 2>&1 | head -20 || echo "(not mapped)"
      echo
    done
    echo "=== tfvars flags ==="
    for f in "${TFVARS[@]}"; do
      echo "--- $f ---"
      grep -E 'public_hostname|enable_domain|advertise_public' "$ROOT/$f" 2>/dev/null || echo "(no domain vars yet)"
    done
    ;;
  verify-hint)
    cat <<'EOF'
1) gcloud domains verify stawi.org
2) gcloud domains list-user-verified
3) ./scripts/setup-public-edge-domains.sh enable-tfvars
4) commit + apply each public app (or push and let CI fan out)
5) For each host, copy DNS records from:
     gcloud beta run domain-mappings describe --domain=<host> \
       --region=europe-west9 --project=<project>
   into Cloudflare (DNS-only until cert Active).
6) After oauth2.stawi.org is live:
     advertise_public_hostname = true on identity-oauth2-hydra

Optional: Cloudflare path aliases api.stawi.org/* → *.stawi.org (not in this repo).

See docs/PUBLIC_EDGE_DNS.md
EOF
    ;;
  enable-tfvars)
    for f in "${TFVARS[@]}"; do
      path="$ROOT/$f"
      [[ -f "$path" ]] || { echo "skip missing $f"; continue; }
      if grep -q 'enable_domain_mapping' "$path"; then
        sed -i 's/enable_domain_mapping[[:space:]]*=[[:space:]]*false/enable_domain_mapping = true/' "$path"
        echo "enabled mapping: $f"
      else
        echo "WARN: no enable_domain_mapping in $f — add public_hostname vars first"
      fi
      grep -E 'public_hostname|enable_domain' "$path" || true
    done
    ;;
  describe)
    for entry in "${HOSTS[@]}"; do
      IFS='|' read -r host project _ <<<"$entry"
      echo "=== $host ($project) ==="
      gcloud beta run domain-mappings describe --domain="$host" \
        --region="$REGION" --project="$project" 2>&1 || echo "(not mapped)"
      echo
    done
    ;;
  *)
    echo "Usage: $0 {status|verify-hint|enable-tfvars|describe}" >&2
    exit 2
    ;;
esac
