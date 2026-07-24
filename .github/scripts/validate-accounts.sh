#!/usr/bin/env bash
# Validate app.yaml account bindings against gcp + neon registries.
# neon.account is optional (GCP-only apps allowed).
set -euo pipefail
ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
GCP="$ROOT/config/gcp-accounts.yaml"
NEON="$ROOT/config/neon-accounts.yaml"
fail=0

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq required" >&2
  exit 1
fi

while IFS= read -r -d '' app_yaml; do
  app="$(basename "$(dirname "$app_yaml")")"
  [[ "$app" == _template ]] && continue

  gcp=$(yq -r '.gcp.account // ""' "$app_yaml")
  neon=$(yq -r '.neon.account // ""' "$app_yaml")
  if [[ -z "$gcp" || "$gcp" == "null" ]]; then
    echo "ERROR: apps/${app} missing gcp.account" >&2
    fail=1
    continue
  fi
  if ! yq -e ".accounts[\"${gcp}\"]" "$GCP" >/dev/null 2>&1; then
    echo "ERROR: apps/${app} unknown gcp.account=${gcp}" >&2
    fail=1
  fi
  if [[ -n "$neon" && "$neon" != "null" ]]; then
    if ! yq -e ".accounts[\"${neon}\"]" "$NEON" >/dev/null 2>&1; then
      echo "ERROR: apps/${app} unknown neon.account=${neon}" >&2
      fail=1
    fi
  fi
  mapfile -t envs < <(yq -r '.envs[]?' "$app_yaml")
  for env in "${envs[@]:-}"; do
    [[ -z "$env" ]] && continue
    if ! yq -e ".accounts[\"${gcp}\"].envs[\"${env}\"]" "$GCP" >/dev/null 2>&1; then
      echo "ERROR: apps/${app} gcp.account=${gcp} missing env ${env}" >&2
      fail=1
    fi
    if [[ -n "$neon" && "$neon" != "null" ]]; then
      if ! yq -e ".accounts[\"${neon}\"].allowed_deploy_envs[] | select(. == \"${env}\")" "$NEON" >/dev/null 2>&1; then
        echo "ERROR: apps/${app} neon.account=${neon} disallows env ${env}" >&2
        fail=1
      fi
    fi
    # Resolve must succeed
    if ! "$ROOT/.github/scripts/resolve-app-context.sh" "$app" "$env" --format=json >/dev/null; then
      echo "ERROR: resolve-app-context failed for ${app}/${env}" >&2
      fail=1
    fi
  done
done < <(find "$ROOT/apps" -mindepth 2 -maxdepth 2 -name app.yaml -print0)

if [[ "$fail" -ne 0 ]]; then
  echo "validate-accounts: FAILED" >&2
  exit 1
fi
echo "validate-accounts: OK"
