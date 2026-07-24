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

  # Domain ↔ Neon account alignment (prevents platform DBs in identity org, etc.)
  domain=$(yq -r '.domain // ""' "$app_yaml")
  gcp_acc="$gcp"
  if [[ -n "$domain" && "$domain" != "null" && -n "$neon" && "$neon" != "null" ]]; then
    if [[ "$domain" != "$neon" ]]; then
      echo "ERROR: apps/${app} domain=${domain} but neon.account=${neon} (must match domain for multi-account isolation)" >&2
      fail=1
    fi
  fi
  if [[ -n "$domain" && "$domain" != "null" && -n "$gcp_acc" && "$gcp_acc" != "null" ]]; then
    if [[ "$domain" != "$gcp_acc" ]]; then
      echo "ERROR: apps/${app} domain=${domain} but gcp.account=${gcp_acc} (must match domain for multi-account isolation)" >&2
      fail=1
    fi
  fi
  # Naming convention: platform-* must use platform Neon (even if domain omitted)
  if [[ "$app" == platform-* && -n "$neon" && "$neon" != "null" && "$neon" != "platform" ]]; then
    echo "ERROR: apps/${app} must use neon.account=platform (got ${neon})" >&2
    fail=1
  fi
  if [[ "$app" == identity-* && -n "$neon" && "$neon" != "null" && "$neon" != "identity" ]]; then
    echo "ERROR: apps/${app} must use neon.account=identity (got ${neon})" >&2
    fail=1
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
