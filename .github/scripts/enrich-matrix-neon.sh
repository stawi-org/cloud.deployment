#!/usr/bin/env bash
# Read JSON matrix [{app,env},...] on stdin; write enriched matrix on stdout:
# [{app,env,neon_account,neon_github_environment},...]
set -euo pipefail
ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
REG="$ROOT/config/neon-accounts.yaml"

MATRIX="$(cat)"
if [[ -z "$MATRIX" || "$MATRIX" == "[]" ]]; then
  echo '[]'
  exit 0
fi

ENRICHED="[]"
while IFS= read -r row; do
  [[ -z "$row" || "$row" == "null" ]] && continue
  APP=$(echo "$row" | jq -r '.app')
  ACC=$(yq -r '.neon.account' "$ROOT/apps/${APP}/app.yaml")
  if [[ -z "$ACC" || "$ACC" == "null" ]]; then
    echo "ERROR: apps/${APP}/app.yaml missing neon.account" >&2
    exit 1
  fi
  GH_ENV=$(yq -r ".accounts[\"${ACC}\"].github_environment" "$REG")
  if [[ -z "$GH_ENV" || "$GH_ENV" == "null" ]]; then
    echo "ERROR: Cannot resolve github_environment for app=${APP} neon.account=${ACC}" >&2
    exit 1
  fi
  ENRICHED=$(echo "$ENRICHED" | jq -c --argjson r "$row" --arg g "$GH_ENV" --arg a "$ACC" \
    '. + [$r + {neon_github_environment:$g, neon_account:$a}]')
done < <(echo "$MATRIX" | jq -c '.[]')

echo "$ENRICHED"
