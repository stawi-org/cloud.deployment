#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/validate-neon-accounts.sh"
FIX="$ROOT/.github/scripts/tests/fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }

# Ensure real repo registry validates against template (uses domain or legacy key)
if command -v yq >/dev/null 2>&1; then
  "$SCRIPT" "$ROOT" || fail "repo validation failed"
else
  echo "SKIP full repo validate (no yq)"
fi

# Fixture: payments prefix enforcement
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/config" "$TMP/apps/evil-app" "$TMP/apps/payment-checkout"
cp "$ROOT/config/neon-accounts.yaml" "$TMP/config/"

cat >"$TMP/apps/evil-app/app.yaml" <<'EOF'
name: evil-app
envs: [stawi-dev]
neon:
  account: payments
runtime: cloudrun
EOF

cat >"$TMP/apps/payment-checkout/app.yaml" <<'EOF'
name: payment-checkout
envs: [stawi-dev]
neon:
  account: payments
runtime: cloudrun
EOF

if "$SCRIPT" "$TMP" 2>/dev/null; then
  fail "expected evil-app under payments to fail prefix policy"
fi

# Only payment-checkout should pass alone
rm -rf "$TMP/apps/evil-app"
"$SCRIPT" "$TMP" || fail "payment-checkout should pass"

# labs cannot use stawi-prod
mkdir -p "$TMP/apps/labs-toy"
cat >"$TMP/apps/labs-toy/app.yaml" <<'EOF'
name: labs-toy
envs: [stawi-prod]
neon:
  account: labs
runtime: cloudrun
EOF
if "$SCRIPT" "$TMP" 2>/dev/null; then
  fail "labs app with stawi-prod should fail"
fi

echo "OK: validate-neon-accounts tests passed"
