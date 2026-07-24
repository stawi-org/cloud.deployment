#!/usr/bin/env bash
# Resolve app.yaml + registries → deployment context for one (app, env).
# Credentials themselves live in SOPS files under credentials/{gcp,neon}/…
# Model: Neon = Postgres; GCP = compute/messaging/SM; accounts selected per app.
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

[[ -f "$APP_YAML" ]] || { echo "ERROR: missing $APP_YAML" >&2; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "ERROR: yq required" >&2; exit 1; }

GCP_ACCOUNT=$(yq -r '.gcp.account // ""' "$APP_YAML")
NEON_ACCOUNT=$(yq -r '.neon.account // ""' "$APP_YAML")
[[ "$NEON_ACCOUNT" == "null" ]] && NEON_ACCOUNT=""

[[ -n "$GCP_ACCOUNT" && "$GCP_ACCOUNT" != "null" ]] || {
  echo "ERROR: apps/${APP}/app.yaml missing gcp.account" >&2
  exit 1
}

if ! yq -e ".envs[] | select(. == \"${ENV}\")" "$APP_YAML" >/dev/null 2>&1; then
  echo "ERROR: env ${ENV} not in apps/${APP}/app.yaml envs" >&2
  exit 1
fi
if ! yq -e ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"]" "$GCP_REG" >/dev/null 2>&1; then
  echo "ERROR: gcp.account=${GCP_ACCOUNT} has no env ${ENV}" >&2
  exit 1
fi

PROJECT_ID=$(yq -r ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].project_id" "$GCP_REG")
REGION=$(yq -r ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].region" "$GCP_REG")
WIF=$(yq -r ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].workload_identity_provider // \"\"" "$GCP_REG")
DEPLOY_SA=$(yq -r ".accounts[\"${GCP_ACCOUNT}\"].envs[\"${ENV}\"].deploy_service_account // \"\"" "$GCP_REG")
GCP_SOPS="credentials/gcp/${GCP_ACCOUNT}/${ENV}/auth.yaml"

USES_NEON="false"
NEON_SOPS=""
if [[ -n "$NEON_ACCOUNT" ]]; then
  USES_NEON="true"
  if ! yq -e ".accounts[\"${NEON_ACCOUNT}\"]" "$NEON_REG" >/dev/null 2>&1; then
    echo "ERROR: unknown neon.account=${NEON_ACCOUNT}" >&2
    exit 1
  fi
  if ! yq -e ".accounts[\"${NEON_ACCOUNT}\"].allowed_deploy_envs[] | select(. == \"${ENV}\")" "$NEON_REG" >/dev/null 2>&1; then
    echo "ERROR: neon.account=${NEON_ACCOUNT} disallows env ${ENV}" >&2
    exit 1
  fi
  NEON_SOPS="credentials/neon/${NEON_ACCOUNT}/auth.yaml"
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
  --arg gcp_sops_path "$GCP_SOPS" \
  --arg neon_sops_path "$NEON_SOPS" \
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
    gcp_sops_path: $gcp_sops_path,
    neon_sops_path: $neon_sops_path,
    labels: $labels
  }')

case "$FORMAT" in
  json) echo "$CTX" ;;
  exports)
    echo "export TF_VAR_project_id=$(jq -r '.project_id' <<<"$CTX")"
    echo "export TF_VAR_region=$(jq -r '.region' <<<"$CTX")"
    echo "export TF_VAR_app_name=$(jq -r '.app' <<<"$CTX")"
    echo "export TF_VAR_platform=$(jq -r '.env' <<<"$CTX")"
    echo "# Decrypt: ./.github/scripts/load-sops-credentials.sh $APP $ENV"
    ;;
  gha)
    [[ -n "${GITHUB_OUTPUT:-}" ]] || { echo "ERROR: GITHUB_OUTPUT not set" >&2; exit 1; }
    while IFS= read -r line; do
      echo "$line" >> "${GITHUB_OUTPUT}"
    done < <(echo "$CTX" | jq -r 'to_entries[] | select(.key != "labels" and .key != "uses_neon") | "\(.key)=\(.value)"')
    echo "uses_neon=$(jq -r '.uses_neon' <<<"$CTX")" >> "${GITHUB_OUTPUT}"
    echo "labels_json=$(echo "$CTX" | jq -c '.labels')" >> "${GITHUB_OUTPUT}"
    ;;
  *) echo "ERROR: unknown format $FORMAT" >&2; exit 1 ;;
esac
