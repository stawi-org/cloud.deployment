#!/usr/bin/env bash
# Deploy stawi-api-gateway Worker + route for api.stawi.org.
#
# Required env:
#   CLOUDFLARE_API_TOKEN  — Account.Workers Scripts:Edit + Zone.Workers Routes:Edit
#                          (+ Zone.DNS:Read for zone_name resolution)
# Optional:
#   CLOUDFLARE_ACCOUNT_ID — if wrangler cannot auto-detect
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "ERROR: set CLOUDFLARE_API_TOKEN" >&2
  exit 1
fi

if [[ ! -d node_modules/wrangler ]]; then
  npm ci 2>/dev/null || npm install
fi

npm run validate
npm test
npm run deploy

echo ""
echo "Deployed. Smoke:"
echo "  GATEWAY_BASE=https://api.stawi.org npm run smoke"
