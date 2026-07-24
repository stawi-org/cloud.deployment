#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/detect-changed-apps.sh"
FIX="$ROOT/.github/scripts/tests/fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }

# Expect: only app "alpha" when only apps/alpha changed
out=$(BASE_REF=fake HEAD_REF=fake CHANGED_FILES_FILE=<(printf '%s\n' 'apps/alpha/cloudrun/main.tf') \
  FIXTURE_ROOT="$FIX" "$SCRIPT" 2>/dev/null) || true
echo "$out" | jq -e '.[] | select(.app=="alpha")' >/dev/null || fail "alpha not detected"
echo "$out" | jq -e 'map(.app) | index("beta")' >/dev/null && fail "beta should be absent" || true

# Expect: module change fans out to consumers
out=$(BASE_REF=fake HEAD_REF=fake CHANGED_FILES_FILE=<(printf '%s\n' 'modules/cloudrun-service/main.tf') \
  FIXTURE_ROOT="$FIX" "$SCRIPT")
echo "$out" | jq -e 'map(.app) | index("alpha")' >/dev/null || fail "module fan-out missing alpha"
echo "$out" | jq -e 'map(.app) | index("beta")' >/dev/null || fail "module fan-out missing beta"

# Expect: empty when only docs change
out=$(BASE_REF=fake HEAD_REF=fake CHANGED_FILES_FILE=<(printf '%s\n' 'README.md') \
  FIXTURE_ROOT="$FIX" "$SCRIPT")
echo "$out" | jq -e '. == []' >/dev/null || fail "docs-only should be empty matrix"

echo "OK: detect-changed-apps tests passed"
