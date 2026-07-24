#!/usr/bin/env bash
# Decrypt SOPS credential files for the selected GCP + Neon accounts.
# Requires SOPS_AGE_KEY (private age key) in the environment.
#
# Usage (from repo root):
#   export SOPS_AGE_KEY='AGE-SECRET-KEY-...'
#   eval "$(./.github/scripts/load-sops-credentials.sh <app> <env>)"
#   # or CI: ./.github/scripts/load-sops-credentials.sh <app> <env> --format=gha
#
# --format=gha      → write GITHUB_ENV / GITHUB_OUTPUT (masks Neon key)
# --format=exports  → shell exports (default)
set -euo pipefail

APP="${1:?app}"
ENV="${2:?env}"
FORMAT="exports"
for a in "${@:3}"; do
  case "$a" in
    --format=*) FORMAT="${a#--format=}" ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CTX=$("$ROOT/.github/scripts/resolve-app-context.sh" "$APP" "$ENV" --format=json)

GCP_ACCOUNT=$(jq -r '.gcp_account' <<<"$CTX")
NEON_ACCOUNT=$(jq -r '.neon_account // empty' <<<"$CTX")
USES_NEON=$(jq -r '.uses_neon' <<<"$CTX")
# Prefer registry non-secret region if SOPS omits it
REG_REGION=$(jq -r '.region // empty' <<<"$CTX")
REG_PROJECT=$(jq -r '.project_id // empty' <<<"$CTX")
REG_WIF=$(jq -r '.workload_identity_provider // empty' <<<"$CTX")
REG_SA=$(jq -r '.deploy_service_account // empty' <<<"$CTX")

if [[ -z "${SOPS_AGE_KEY:-}" ]]; then
  echo "ERROR: SOPS_AGE_KEY is required to decrypt credentials/" >&2
  exit 1
fi
command -v sops >/dev/null 2>&1 || { echo "ERROR: sops required" >&2; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "ERROR: yq required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

export SOPS_AGE_KEY

GCP_SOPS="$ROOT/credentials/gcp/${GCP_ACCOUNT}/${ENV}/auth.yaml"
if [[ ! -f "$GCP_SOPS" ]]; then
  echo "ERROR: missing $GCP_SOPS — run bootstrap-gcp-account.sh for ${GCP_ACCOUNT}/${ENV}" >&2
  exit 1
fi

GCP_JSON=$(sops -d "$GCP_SOPS" | yq -o=json '.')
# support auth: wrapper or flat
PROJECT_ID=$(jq -r '.auth.project_id // .project_id // empty' <<<"$GCP_JSON")
REGION=$(jq -r '.auth.region // .region // empty' <<<"$GCP_JSON")
WIF=$(jq -r '.auth.workload_identity_provider // .workload_identity_provider // empty' <<<"$GCP_JSON")
DEPLOY_SA=$(jq -r '.auth.deploy_service_account // .deploy_service_account // empty' <<<"$GCP_JSON")

# Fall back to public registry (same values; useful if SOPS is sparse)
[[ -n "$PROJECT_ID" ]] || PROJECT_ID="$REG_PROJECT"
[[ -n "$REGION" ]] || REGION="$REG_REGION"
[[ -n "$WIF" ]] || WIF="$REG_WIF"
[[ -n "$DEPLOY_SA" ]] || DEPLOY_SA="$REG_SA"

[[ -n "$PROJECT_ID" && -n "$WIF" && -n "$DEPLOY_SA" ]] || {
  echo "ERROR: decrypted GCP auth missing project_id / WIF / deploy_service_account" >&2
  exit 1
}
[[ -n "$REGION" ]] || REGION="europe-west1"

NEON_API_KEY=""
if [[ "$USES_NEON" == "true" ]]; then
  NEON_SOPS="$ROOT/credentials/neon/${NEON_ACCOUNT}/auth.yaml"
  if [[ ! -f "$NEON_SOPS" ]]; then
    echo "ERROR: missing $NEON_SOPS — run bootstrap-neon-account.sh for ${NEON_ACCOUNT}" >&2
    exit 1
  fi
  NEON_API_KEY=$(sops -d "$NEON_SOPS" | yq -r '.auth.api_key // .api_key // empty')
  [[ -n "$NEON_API_KEY" && "$NEON_API_KEY" != "null" ]] || {
    echo "ERROR: decrypted Neon auth missing api_key" >&2
    exit 1
  }
fi

emit_gha() {
  {
    echo "project_id=${PROJECT_ID}"
    echo "region=${REGION}"
    echo "workload_identity_provider=${WIF}"
    echo "deploy_service_account=${DEPLOY_SA}"
    echo "gcp_account=${GCP_ACCOUNT}"
    echo "neon_account=${NEON_ACCOUNT}"
    echo "uses_neon=${USES_NEON}"
  } >> "${GITHUB_OUTPUT}"
  {
    echo "TF_VAR_project_id=${PROJECT_ID}"
    echo "TF_VAR_region=${REGION}"
    if [[ -n "$NEON_API_KEY" ]]; then
      echo "::add-mask::${NEON_API_KEY}"
      echo "TF_VAR_neon_api_key=${NEON_API_KEY}"
    else
      echo "TF_VAR_neon_api_key=unused"
    fi
  } >> "${GITHUB_ENV}"
}

emit_exports() {
  echo "export TF_VAR_project_id=$(printf %q "$PROJECT_ID")"
  echo "export TF_VAR_region=$(printf %q "$REGION")"
  echo "export CLOUD_DEPLOY_WIF=$(printf %q "$WIF")"
  echo "export CLOUD_DEPLOY_SA=$(printf %q "$DEPLOY_SA")"
  if [[ -n "$NEON_API_KEY" ]]; then
    echo "export TF_VAR_neon_api_key=$(printf %q "$NEON_API_KEY")"
  else
    echo "export TF_VAR_neon_api_key=unused"
  fi
}

case "$FORMAT" in
  gha) emit_gha ;;
  exports|*) emit_exports ;;
esac
