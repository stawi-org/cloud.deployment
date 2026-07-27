#!/usr/bin/env bash
# Create Cloud Run domain mappings for stable stawi.org hostnames (europe-west1).
#
# Prerequisites:
#   - Services already deployed in europe-west1
#   - stawi.org verified: gcloud domains list-user-verified
#   - gcloud auth with permission to create domainmappings
#
# Usage:
#   ./scripts/create-domain-mappings.sh          # create + print DNS records
#   ./scripts/create-domain-mappings.sh status    # describe existing
#   ./scripts/create-domain-mappings.sh dns       # print resourceRecords only
set -euo pipefail

REGION="${REGION:-europe-west1}"
PROJECT="${PROJECT:-stawi-identity}"
CMD="${1:-create}"

# domain|service
MAPS=(
  "accounts.stawi.org|identity-authentication"
  "oauth2.stawi.org|identity-oauth2-hydra"
  "oauth2-w.stawi.org|identity-oauth2-hydra-admin"
  "authz.stawi.org|identity-authorization-keto-read"
  "authz-w.stawi.org|identity-authorization-keto-write"
)

create_one() {
  local domain=$1 svc=$2
  echo "=== map $domain → $svc ($REGION / $PROJECT) ==="
  if gcloud beta run domain-mappings describe --domain="$domain" \
    --region="$REGION" --project="$PROJECT" &>/dev/null; then
    echo "already exists"
  else
    gcloud beta run domain-mappings create \
      --service="$svc" \
      --domain="$domain" \
      --region="$REGION" \
      --project="$PROJECT"
  fi
}

describe_dns() {
  local domain=$1
  echo "=== DNS for $domain ==="
  gcloud beta run domain-mappings describe --domain="$domain" \
    --region="$REGION" --project="$PROJECT" \
    --format='yaml(status.resourceRecords,status.conditions)' 2>&1 || echo "(missing)"
  echo
}

case "$CMD" in
  create)
    for entry in "${MAPS[@]}"; do
      domain="${entry%%|*}"
      svc="${entry##*|}"
      create_one "$domain" "$svc"
    done
    echo
    echo "Install these DNS records at Cloudflare (often grey during first cert issue):"
    for entry in "${MAPS[@]}"; do
      describe_dns "${entry%%|*}"
    done
    ;;
  status|dns)
    for entry in "${MAPS[@]}"; do
      describe_dns "${entry%%|*}"
    done
    ;;
  *)
    echo "usage: $0 [create|status|dns]" >&2
    exit 2
    ;;
esac
