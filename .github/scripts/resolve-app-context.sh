#!/usr/bin/env bash
# Resolve app.yaml + registries → deployment context for one (app, env).
#
# Model: docs/superpowers/specs/2026-07-24-account-selection-and-ci-credentials.md
#
# Usage:
#   resolve-app-context.sh <app> <env> [--format=json|exports|gha]
set -euo pipefail

APP="${1:?app name required}"
ENV="${2:?env required (e.g. stawi-prod)}"
FORMAT="json"
for a in "${@:3}"; do
  case "$a" in
    --format=*) FORMAT="${a#--format=}" ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_YAML="$ROOT/apps/${APP}/app.yaml"
GCP_REG="$ROOT/config/gcp-accounts.yaml"
NEON_REG="$ROOT/config/neon-accounts.yaml"

if [[ ! -f "$APP_YAML" ]]; then
  echo "ERROR: missing $APP_YAML" >&2
  exit 1
fi
if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq (mikefarah) required" >&2
  exit 1
fi

GCP_ACCOUNT=$(yq -r '.gcp.account // ""' "$APP_YAML")
NEON_ACCOUNT=$(yq -r '.neon.account // ""' "$APP_YAML")
# empty neon.account means app does not use Neon
if [[ "$NEON_ACCOUNT" == "null" ]]; then
  NEON_ACCOUNT=""
fi

if [[ -z "$GCP_ACCOUNT" || "$GCP_ACCOUNT" == "null" ]]; then
  echo "ERROR: apps/${APP}/app.yaml missing gcp.account" >&2
  exit 1
fi

if ! yq -e ".envs[] | select(. == \"${ENV}\")" "$APP_YAML" >/dev/null 2>&1; then
  echo "ERROR: env ${ENV} not in apps/${APP}/app.yaml envs" >&2
  exit 1
fi

if ! yq -e ".accounts[\"${GCP_ACCOUNT}\"]" "$GCP_REG" >/dev/null 2>&1; then
  echo "ERROR: unknown gcp.account=${GCP_ACCOUNT}" >&2
  exit 1
fi
if ! yq -e ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"]" "$GCP_REG" >/dev/null 2>&1; then
  echo "ERROR: gcp.account=${GCP_ACCOUNT} has no env slice ${ENV}" >&2
  exit 1
fi

PROJECT_ID=$(yq -r ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].project_id" "$GCP_REG")
REGION=$(yq -r ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].region" "$GCP_REG")
WIF=$(yq -r ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].workload_identity_provider" "$GCP_REG")
DEPLOY_SA=$(yq -r ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].deploy_service_account" "$GCP_REG")
# Optional protection-only GH env (no secrets): deploy--{account}--{env}
PROTECTION_ENV=$(yq -r ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].protection_environment // \"\"" "$GCP_REG")
if [[ "$PROTECTION_ENV" == "null" ]]; then PROTECTION_ENV=""; fi

NEON_GH_ENV=""
USES_NEON="false"
if [[ -n "$NEON_ACCOUNT" ]]; then
  USES_NEON="true"
  if ! yq -e ".accounts[\"${NEON_ACCOUNT}\"]" "$NEON_REG" >/dev/null 2>&1; then
    echo "ERROR: unknown neon.account=${NEON_ACCOUNT}" >&2
    exit 1
  fi
  if ! yq -e ".accounts[\"${NEON_ACCOUNT}\"].allowed_deploy_envs[] | select(. == \"${ENV}\")" "$NEON_REG" >/dev/null 2>&1; then
    echo "ERROR: neon.account=${NEON_ACCOUNT} does not allow env ${ENV}" >&2
    exit 1
  fi
  NEON_GH_ENV=$(yq -r ".accounts[\"${NEON_ACCOUNT}\"].github_environment // \"\"" "$NEON_REG")
  if [[ -z "$NEON_GH_ENV" || "$NEON_GH_ENV" == "null" ]]; then
    NEON_GH_ENV="neon--${NEON_ACCOUNT}"
  fi
  # Enforce naming convention
  expected="neon--${NEON_ACCOUNT}"
  if [[ "$NEON_GH_ENV" != "$expected" ]]; then
    echo "WARNING: neon.account=${NEON_ACCOUNT} github_environment='${NEON_GH_ENV}' should be '${expected}'" >&2
  fi
fi

# Job GH environment: Neon credential env when Neon is used; else optional protection env
JOB_ENVIRONMENT=""
if [[ "$USES_NEON" == "true" ]]; then
  JOB_ENVIRONMENT="$NEON_GH_ENV"
elif [[ -n "$PROTECTION_ENV" ]]; then
  JOB_ENVIRONMENT="$PROTECTION_ENV"
fi

LABELS_JSON=$(yq -o=json -I=0 ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].labels // {}" "$GCP_REG")

CTX=$(jq -nc \
  --arg app "$APP" \
  --arg env "$ENV" \
  --arg gcp_account "$GCP_ACCOUNT" \
  --arg neon_account "$NEON_ACCOUNT" \
  --arg uses_neon "$USES_NEON" \
  --arg project_id "$PROJECT_ID" \
  --arg region "$REGION" \
  --arg workload_identity_provider "$WIF" \
  --arg deploy_service_account "$DEPLOY_SA" \
  --arg protection_environment "$PROTECTION_ENV" \
  --arg neon_github_environment "$NEON_GH_ENV" \
  --arg job_environment "$JOB_ENVIRONMENT" \
  --argjson labels "$LABELS_JSON" \
  '{
    app: $app,
    env: $env,
    gcp_account: $gcp_account,
    neon_account: $neon_account,
    uses_neon: ($uses_neon == "true"),
    project_id: $project_id,
    region: $region,
    workload_identity_provider: $workload_identity_provider,
    deploy_service_account: $deploy_service_account,
    protection_environment: $protection_environment,
    neon_github_environment: $neon_github_environment,
    job_environment: $job_environment,
    labels: $labels
  }')

case "$FORMAT" in
  json) echo "$CTX" ;;
  exports)
    echo "export TF_VAR_project_id=$(jq -r '.project_id' <<<"$CTX")"
    echo "export TF_VAR_region=$(jq -r '.region' <<<"$CTX")"
    echo "export TF_VAR_app_name=$(jq -r '.app' <<<"$CTX")"
    echo "export TF_VAR_platform=$(jq -r '.env' <<<"$CTX")"
    if jq -e '.uses_neon' <<<"$CTX" >/dev/null; then
      echo "# Neon: GitHub Environment $(jq -r '.neon_github_environment' <<<"$CTX") secret API_KEY"
    else
      echo "# Neon: not used by this app"
    fi
    ;;
  gha)
    if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
      echo "ERROR: GITHUB_OUTPUT not set" >&2
      exit 1
    fi
    while IFS= read -r line; do
      echo "$line" >> "${GITHUB_OUTPUT}"
    done < <(echo "$CTX" | jq -r 'to_entries[] | select(.key != "labels" and .key != "uses_neon") | "\(.key)=\(.value)"')
    echo "uses_neon=$(jq -r '.uses_neon' <<<"$CTX")" >> "${GITHUB_OUTPUT}"
    echo "labels_json=$(echo "$CTX" | jq -c '.labels')" >> "${GITHUB_OUTPUT}"
    ;;
  *)
    echo "ERROR: unknown format $FORMAT" >&2
    exit 1
    ;;
esac
