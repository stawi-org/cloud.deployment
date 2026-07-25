#!/usr/bin/env bash
# Create Cloud Run domain mappings as the *user* (not CI SA).
# Domain must be verified for this Google account:
#   gcloud domains list-user-verified   # must include stawi.org
#   If empty: open Search Console → Domain property stawi.org → Verify
#   (TXT google-site-verification=… is already on stawi.org apex)
#
# Usage:
#   ./scripts/create-domain-mappings.sh
#   ./scripts/create-domain-mappings.sh --describe
set -euo pipefail

REGION="${REGION:-europe-west9}"
DESCRIBE_ONLY=false
[[ "${1:-}" == "--describe" ]] && DESCRIBE_ONLY=true

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

echo "Account: $(gcloud config get-value account 2>/dev/null)"
echo "Verified domains:"
gcloud domains list-user-verified 2>&1 || true
echo

if ! gcloud domains list-user-verified --format='value(id)' 2>/dev/null | grep -qiE 'stawi\.org'; then
  cat <<'EOF'
ERROR: stawi.org is not verified for this gcloud account.

DNS already has:
  google-site-verification=zSyjIq6uWNhB12YRZoPhiAYfOrGYafeEuldX6Sn7Ttg

Finish ownership for *this* user (bwire@stawi.org):
  1. Open https://search.google.com/search-console
  2. Add property → Domain → stawi.org (not URL-prefix)
  3. Click Verify (TXT is already present)
  4. Re-run: gcloud domains list-user-verified
  5. Re-run this script

Note: verification under a different Google account does not count for this gcloud login.
Cloud Run domain mappings must be created with a user that owns the Search Console property
(or a user added as owner there). CI service accounts generally cannot create them.
EOF
  exit 1
fi

echo "=== Cloudflare DNS records to create (after mapping) ==="
echo "Prefer DNS-only (grey cloud) until certificate Active."
echo

for entry in "${HOSTS[@]}"; do
  IFS='|' read -r domain project service <<<"$entry"
  if [[ "$DESCRIBE_ONLY" == true ]]; then
    echo "----- $domain -----"
    gcloud beta run domain-mappings describe --domain="$domain" \
      --region="$REGION" --project="$project" 2>&1 || echo "(not mapped)"
    echo
    continue
  fi

  echo "Mapping $domain → $project/$service ..."
  if gcloud beta run domain-mappings describe --domain="$domain" \
      --region="$REGION" --project="$project" >/dev/null 2>&1; then
    echo "  already exists"
  else
    gcloud beta run domain-mappings create \
      --service="$service" \
      --domain="$domain" \
      --region="$REGION" \
      --project="$project"
    echo "  created"
  fi

  # Print DNS records for Cloudflare
  gcloud beta run domain-mappings describe --domain="$domain" \
    --region="$REGION" --project="$project" \
    --format='yaml(status.resourceRecords)' 2>/dev/null || true
  echo
done

echo "Done. Add the resourceRecords above in Cloudflare (DNS-only until Active)."
echo "Then: ./scripts/create-domain-mappings.sh --describe  # check CertificateActive"
