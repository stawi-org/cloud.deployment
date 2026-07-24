#!/usr/bin/env bash
# Validate apps/*/app.yaml neon.account against config/neon-accounts.yaml policy.
# Usage: validate-neon-accounts.sh [repo-root]
set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
REG="$ROOT/config/neon-accounts.yaml"

if [[ ! -f "$REG" ]]; then
  echo "ERROR: missing $REG" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq (mikefarah) is required" >&2
  exit 1
fi

fail=0
warn=0

account_exists() {
  local key="$1"
  yq -e ".accounts[\"${key}\"]" "$REG" >/dev/null 2>&1
}

while IFS= read -r -d '' app_yaml; do
  app="$(basename "$(dirname "$app_yaml")")"
  if [[ "$app" == _template ]]; then
    # Template may use a domain placeholder; still must be a real registry key
    :
  fi

  acc="$(yq -r '.neon.account // ""' "$app_yaml")"
  if [[ -z "$acc" || "$acc" == "null" ]]; then
    echo "ERROR: apps/${app}/app.yaml missing neon.account" >&2
    fail=1
    continue
  fi

  if ! account_exists "$acc"; then
    echo "ERROR: apps/${app}/app.yaml neon.account='${acc}' not in config/neon-accounts.yaml" >&2
    fail=1
    continue
  fi

  dep="$(yq -r ".accounts[\"${acc}\"].deprecated // false" "$REG")"
  if [[ "$dep" == "true" ]]; then
    msg="$(yq -r ".accounts[\"${acc}\"].deprecated_message // \"deprecated account\"" "$REG")"
    echo "WARN: apps/${app} uses deprecated neon.account='${acc}': ${msg}" >&2
    warn=1
  fi

  # allowed_deploy_envs: every env listed on the app must be allowed for the account
  mapfile -t app_envs < <(yq -r '.envs[]?' "$app_yaml")
  for env in "${app_envs[@]:-}"; do
    [[ -z "$env" ]] && continue
    if ! yq -e ".accounts[\"${acc}\"].allowed_deploy_envs[] | select(. == \"${env}\")" "$REG" >/dev/null 2>&1; then
      echo "ERROR: apps/${app} env '${env}' not in allowed_deploy_envs for neon.account='${acc}'" >&2
      fail=1
    fi
  done

  # allowed_app_prefixes: if non-empty, app name must start with one
  prefixes="$(yq -r ".accounts[\"${acc}\"].allowed_app_prefixes // [] | .[]" "$REG" | paste -sd'|' - || true)"
  if [[ -n "$prefixes" ]]; then
    ok=0
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      if [[ "$app" == "$p"* ]]; then
        ok=1
        break
      fi
    done < <(yq -r ".accounts[\"${acc}\"].allowed_app_prefixes[]" "$REG")
    if [[ "$ok" -ne 1 ]]; then
      echo "ERROR: apps/${app} name does not match allowed_app_prefixes for neon.account='${acc}': $(yq -r ".accounts[\"${acc}\"].allowed_app_prefixes | join(\", \")" "$REG")" >&2
      fail=1
    fi
  fi

  # Registry completeness
  gh_env="$(yq -r ".accounts[\"${acc}\"].github_environment // \"\"" "$REG")"
  vault="$(yq -r ".accounts[\"${acc}\"].vault_path // \"\"" "$REG")"
  if [[ -z "$gh_env" || "$gh_env" == "null" ]]; then
    echo "ERROR: registry account '${acc}' missing github_environment" >&2
    fail=1
  fi
  if [[ -z "$vault" || "$vault" == "null" ]]; then
    echo "ERROR: registry account '${acc}' missing vault_path" >&2
    fail=1
  fi
done < <(find "$ROOT/apps" -mindepth 2 -maxdepth 2 -name app.yaml -print0 2>/dev/null)

# Registry internal consistency
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  gh_env="$(yq -r ".accounts[\"${key}\"].github_environment" "$REG")"
  if [[ -z "$gh_env" || "$gh_env" == "null" ]]; then
    echo "ERROR: accounts.${key} missing github_environment" >&2
    fail=1
  fi
done < <(yq -r '.accounts | keys | .[]' "$REG")

if [[ "$fail" -ne 0 ]]; then
  echo "validate-neon-accounts: FAILED" >&2
  exit 1
fi

echo "validate-neon-accounts: OK (warnings=${warn})"
exit 0
