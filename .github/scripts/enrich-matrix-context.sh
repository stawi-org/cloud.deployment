#!/usr/bin/env bash
# stdin: JSON [{app,env},...]
# stdout: enriched with neon + gcp context fields for CI matrix
set -euo pipefail
ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
RESOLVE="$ROOT/.github/scripts/resolve-app-context.sh"

MATRIX="$(cat)"
if [[ -z "$MATRIX" || "$MATRIX" == "[]" ]]; then
  echo '[]'
  exit 0
fi

ENRICHED="[]"
while IFS= read -r row; do
  [[ -z "$row" || "$row" == "null" ]] && continue
  APP=$(echo "$row" | jq -r '.app')
  ENV=$(echo "$row" | jq -r '.env')
  CTX=$("$RESOLVE" "$APP" "$ENV" --format=json)
  ENRICHED=$(echo "$ENRICHED" | jq -c --argjson r "$row" --argjson c "$CTX" '. + [$r + $c]')
done < <(echo "$MATRIX" | jq -c '.[]')

echo "$ENRICHED"
