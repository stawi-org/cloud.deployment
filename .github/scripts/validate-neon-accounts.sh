#!/usr/bin/env bash
# Validate apps/*/app.yaml neon.account against config/neon-accounts.yaml policy.
# Apps without neon.account are skipped (GCP-only is allowed).
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

  acc="$(yq -r '.neon.account // ""' "$app_yaml")"
  if [[ -z "$acc" || "$acc" == "null" ]]; then
    # Neon is optional — apps without neon.account skip Neon policy
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

  # allowed_app_prefixes / allowed_app_names: if either is non-empty, the app
  # name must start with an allowed prefix or equal an allowed name exactly.
  prefixes="$(yq -r ".accounts[\"${acc}\"].allowed_app_prefixes // [] | .[]" "$REG" | paste -sd'|' - || true)"
  names="$(yq -r ".accounts[\"${acc}\"].allowed_app_names // [] | .[]" "$REG" | paste -sd'|' - || true)"
  if [[ -n "$prefixes" || -n "$names" ]]; then
    ok=0
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      if [[ "$app" == "$p"* ]]; then
        ok=1
        break
      fi
    done < <(yq -r ".accounts[\"${acc}\"].allowed_app_prefixes // [] | .[]" "$REG")
    if [[ "$ok" -ne 1 ]]; then
      while IFS= read -r n; do
        [[ -z "$n" ]] && continue
        if [[ "$app" == "$n" ]]; then
          ok=1
          break
        fi
      done < <(yq -r ".accounts[\"${acc}\"].allowed_app_names // [] | .[]" "$REG")
    fi
    if [[ "$ok" -ne 1 ]]; then
      echo "ERROR: apps/${app} name does not match allowed_app_prefixes/allowed_app_names for neon.account='${acc}': $(yq -r "(.accounts[\"${acc}\"].allowed_app_prefixes // []) + (.accounts[\"${acc}\"].allowed_app_names // []) | join(\", \")" "$REG")" >&2
      fail=1
    fi
  fi

  # Optional: SOPS path should exist once account is bootstrapped (warn only for known accounts with path set)
  sops_path="$(yq -r ".accounts[\"${acc}\"].sops_auth_path // \"\"" "$REG")"
  if [[ -n "$sops_path" && "$sops_path" != "null" && ! -f "$ROOT/$sops_path" ]]; then
    echo "WARN: apps/${app} neon.account=${acc} missing SOPS file $sops_path (run bootstrap-neon-account.sh)" >&2
    warn=1
  fi
done < <(find "$ROOT/apps" -mindepth 2 -maxdepth 2 -name app.yaml -print0 2>/dev/null)

if [[ "$fail" -ne 0 ]]; then
  echo "validate-neon-accounts: FAILED" >&2
  exit 1
fi

echo "validate-neon-accounts: OK (warnings=${warn})"
exit 0
