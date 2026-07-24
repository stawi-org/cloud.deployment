#!/usr/bin/env bash
# Resolve app.yaml + registries → deployment context for one (app, env).
# Usage:
#   resolve-app-context.sh <app> <env> [--format=json|exports|gha]
# --format=gha writes GITHUB_OUTPUT keys when running in Actions.
set -euo pipefail

APP="${1:?app name required}"
ENV="${2:?env required (e.g. stawi-dev)}"
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
if [[ -z "$GCP_ACCOUNT" || "$GCP_ACCOUNT" == "null" ]]; then
  echo "ERROR: apps/${APP}/app.yaml missing gcp.account" >&2
  exit 1
fi
if [[ -z "$NEON_ACCOUNT" || "$NEON_ACCOUNT" == "null" ]]; then
  echo "ERROR: apps/${APP}/app.yaml missing neon.account" >&2
  exit 1
fi

# Env must be listed on the app
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
GCP_GH_ENV=$(yq -r ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].github_environment // \"\"" "$GCP_REG")

if ! yq -e ".accounts[\"${NEON_ACCOUNT}\"]" "$NEON_REG" >/dev/null 2>&1; then
  echo "ERROR: unknown neon.account=${NEON_ACCOUNT}" >&2
  exit 1
fi
if ! yq -e ".accounts[\"${NEON_ACCOUNT}\"].allowed_deploy_envs[] | select(. == \"${ENV}\")" "$NEON_REG" >/dev/null 2>&1; then
  echo "ERROR: neon.account=${NEON_ACCOUNT} does not allow env ${ENV}" >&2
  exit 1
fi

NEON_GH_ENV=$(yq -r ".accounts[\"${NEON_ACCOUNT}\"].github_environment" "$NEON_REG")
NEON_SM_GCP=$(yq -r ".accounts[\"${NEON_ACCOUNT}\"].secret_manager.gcp_account // \"\"" "$NEON_REG")
NEON_SM_ID=$(yq -r ".accounts[\"${NEON_ACCOUNT}\"].secret_manager.secret_id // \"\"" "$NEON_REG")
NEON_SM_PROJECT=""
if [[ -n "$NEON_SM_GCP" && "$NEON_SM_GCP" != "null" ]]; then
  # Neon org key secret lives in that domain's GCP project for this env
  NEON_SM_PROJECT=$(yq -r ".accounts[\"${NEON_SM_GCP}\"].envs[\"${ENV}\"].project_id // \"\"" "$GCP_REG")
  if [[ -z "$NEON_SM_PROJECT" || "$NEON_SM_PROJECT" == "null" ]]; then
    # labs has only stawi-dev — try same env only
    echo "ERROR: cannot resolve project for neon secret_manager.gcp_account=${NEON_SM_GCP} env=${ENV}" >&2
    exit 1
  fi
fi

# Labels as JSON object
LABELS_JSON=$(yq -o=json -I=0 ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].labels // {}" "$GCP_REG")

CTX=$(jq -nc \
  --arg app "$APP" \
  --arg env "$ENV" \
  --arg gcp_account "$GCP_ACCOUNT" \
  --arg neon_account "$NEON_ACCOUNT" \
  --arg project_id "$PROJECT_ID" \
  --arg region "$REGION" \
  --arg workload_identity_provider "$WIF" \
  --arg deploy_service_account "$DEPLOY_SA" \
  --arg gcp_github_environment "$GCP_GH_ENV" \
  --arg neon_github_environment "$NEON_GH_ENV" \
  --arg neon_sm_project_id "$NEON_SM_PROJECT" \
  --arg neon_sm_secret_id "$NEON_SM_ID" \
  --argjson labels "$LABELS_JSON" \
  '{
    app: $app,
    env: $env,
    gcp_account: $gcp_account,
    neon_account: $neon_account,
    project_id: $project_id,
    region: $region,
    workload_identity_provider: $workload_identity_provider,
    deploy_service_account: $deploy_service_account,
    gcp_github_environment: $gcp_github_environment,
    neon_github_environment: $neon_github_environment,
    neon_sm_project_id: $neon_sm_project_id,
    neon_sm_secret_id: $neon_sm_secret_id,
    labels: $labels
  }')

case "$FORMAT" in
  json) echo "$CTX" ;;
  exports)
    echo "export TF_VAR_project_id=$(jq -r '.project_id' <<<"$CTX")"
    echo "export TF_VAR_region=$(jq -r '.region' <<<"$CTX")"
    echo "export TF_VAR_app_name=$(jq -r '.app' <<<"$CTX")"
    echo "export TF_VAR_platform=$(jq -r '.env' <<<"$CTX")"
    echo "# Fetch Neon key: gcloud secrets versions access latest --secret=$(jq -r '.neon_sm_secret_id' <<<"$CTX") --project=$(jq -r '.neon_sm_project_id' <<<"$CTX")"
    ;;
  gha)
    if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
      echo "ERROR: GITHUB_OUTPUT not set (not running in Actions?)" >&2
      exit 1
    fi
    while IFS= read -r line; do
      echo "$line" >> "${GITHUB_OUTPUT}"
    done < <(echo "$CTX" | jq -r 'to_entries[] | select(.key != "labels") | "\(.key)=\(.value)"')
    echo "labels_json=$(echo "$CTX" | jq -c '.labels')" >> "${GITHUB_OUTPUT}"
    ;;
  *)
    echo "ERROR: unknown format $FORMAT" >&2
    exit 1
    ;;
esac
