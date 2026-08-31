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
SUPABASE_ACCOUNT=$(jq -r '.supabase_account // empty' <<<"$CTX")
USES_SUPABASE=$(jq -r '.uses_supabase // false' <<<"$CTX")
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
SOPS_REGION=$(jq -r '.auth.region // .region // empty' <<<"$GCP_JSON")
WIF=$(jq -r '.auth.workload_identity_provider // .workload_identity_provider // empty' <<<"$GCP_JSON")
DEPLOY_SA=$(jq -r '.auth.deploy_service_account // .deploy_service_account // empty' <<<"$GCP_JSON")

# Fall back to public registry (same values; useful if SOPS is sparse)
[[ -n "$PROJECT_ID" ]] || PROJECT_ID="$REG_PROJECT"
[[ -n "$WIF" ]] || WIF="$REG_WIF"
[[ -n "$DEPLOY_SA" ]] || DEPLOY_SA="$REG_SA"

# Region is non-secret: config/gcp-accounts.yaml is source of truth (overrides SOPS).
# Keeps region migrations from being blocked by encrypted auth.yaml drift.
REGION="${REG_REGION:-}"
[[ -n "$REGION" ]] || REGION="$SOPS_REGION"

[[ -n "$PROJECT_ID" && -n "$WIF" && -n "$DEPLOY_SA" ]] || {
  echo "ERROR: decrypted GCP auth missing project_id / WIF / deploy_service_account" >&2
  exit 1
}
[[ -n "$REGION" ]] || REGION="europe-west1"
if [[ -n "$SOPS_REGION" && -n "$REG_REGION" && "$SOPS_REGION" != "$REG_REGION" ]]; then
  echo "::warning::SOPS auth region ($SOPS_REGION) differs from gcp-accounts.yaml ($REG_REGION); using registry region"
fi

NEON_API_KEY=""
NEON_ORG_ID=$(jq -r '.neon_org_id // empty' <<<"$CTX")
if [[ "$USES_NEON" == "true" ]]; then
  NEON_SOPS="$ROOT/credentials/neon/${NEON_ACCOUNT}/auth.yaml"
  if [[ ! -f "$NEON_SOPS" ]]; then
    echo "ERROR: missing $NEON_SOPS — run bootstrap-neon-account.sh for ${NEON_ACCOUNT}" >&2
    exit 1
  fi
  NEON_JSON=$(sops -d "$NEON_SOPS" | yq -o=json '.')
  NEON_API_KEY=$(jq -r '.auth.api_key // .api_key // empty' <<<"$NEON_JSON")
  # Prefer SOPS neon_org_id when present; else registry
  SOPS_ORG=$(jq -r '.auth.neon_org_id // .neon_org_id // empty' <<<"$NEON_JSON")
  if [[ -n "$SOPS_ORG" && "$SOPS_ORG" != "null" ]]; then
    NEON_ORG_ID="$SOPS_ORG"
  fi
  [[ -n "$NEON_API_KEY" && "$NEON_API_KEY" != "null" ]] || {
    echo "ERROR: decrypted Neon auth missing api_key" >&2
    exit 1
  }
  # Resolve org id from Neon API when registry/SOPS omitted it (common for new org keys).
  if [[ -z "$NEON_ORG_ID" || "$NEON_ORG_ID" == "null" ]]; then
    if command -v curl >/dev/null 2>&1; then
      # Org API keys are scoped; /projects lists that org's projects and includes org_id.
      NEON_PROJ_JSON=$(curl -fsS \
        -H "Authorization: Bearer ${NEON_API_KEY}" \
        -H "Accept: application/json" \
        "https://console.neon.tech/api/v2/projects?limit=1" 2>/dev/null || true)
      NEON_ORG_ID=$(jq -r '
          .projects[0].org_id
          // .projects[0].organization_id
          // .organization.id
          // .org_id
          // empty
        ' <<<"${NEON_PROJ_JSON:-{}}" 2>/dev/null || true)
      if [[ -z "$NEON_ORG_ID" || "$NEON_ORG_ID" == "null" ]]; then
        NEON_ORG_JSON=$(curl -fsS \
          -H "Authorization: Bearer ${NEON_API_KEY}" \
          -H "Accept: application/json" \
          "https://console.neon.tech/api/v2/users/me/organizations" 2>/dev/null || true)
        NEON_ORG_ID=$(jq -r '
            .organizations[0].id
            // .organizations[0].org_id
            // empty
          ' <<<"${NEON_ORG_JSON:-{}}" 2>/dev/null || true)
      fi
    fi
  fi
  [[ -n "$NEON_ORG_ID" && "$NEON_ORG_ID" != "null" ]] || {
    echo "ERROR: neon.account=${NEON_ACCOUNT} missing neon_org_id in registry/SOPS and could not resolve via Neon API" >&2
    exit 1
  }
  echo "Resolved neon.account=${NEON_ACCOUNT} org_id=${NEON_ORG_ID}" >&2
fi

SUPABASE_ACCESS_TOKEN=""
SUPABASE_ORG_ID=$(jq -r '.supabase_org_id // empty' <<<"$CTX")
if [[ "$USES_SUPABASE" == "true" ]]; then
  SUPABASE_SOPS="$ROOT/credentials/supabase/${SUPABASE_ACCOUNT}/auth.yaml"
  if [[ ! -f "$SUPABASE_SOPS" ]]; then
    echo "ERROR: missing $SUPABASE_SOPS — encrypt the org access token first (see config/supabase-accounts.yaml)" >&2
    exit 1
  fi
  SUPABASE_JSON=$(sops -d "$SUPABASE_SOPS" | yq -o=json '.')
  SUPABASE_ACCESS_TOKEN=$(jq -r '.auth.access_token // .access_token // empty' <<<"$SUPABASE_JSON")
  # Prefer SOPS supabase_org_id when present; else registry
  SOPS_SB_ORG=$(jq -r '.auth.supabase_org_id // .supabase_org_id // empty' <<<"$SUPABASE_JSON")
  if [[ -n "$SOPS_SB_ORG" && "$SOPS_SB_ORG" != "null" ]]; then
    SUPABASE_ORG_ID="$SOPS_SB_ORG"
  fi
  [[ -n "$SUPABASE_ACCESS_TOKEN" && "$SUPABASE_ACCESS_TOKEN" != "null" ]] || {
    echo "ERROR: decrypted Supabase auth missing access_token" >&2
    exit 1
  }
  [[ -n "$SUPABASE_ORG_ID" && "$SUPABASE_ORG_ID" != "null" ]] || {
    echo "ERROR: supabase.account=${SUPABASE_ACCOUNT} missing supabase_org_id in registry/SOPS" >&2
    exit 1
  }
  echo "Resolved supabase.account=${SUPABASE_ACCOUNT} org_id=${SUPABASE_ORG_ID}" >&2
fi

emit_gha() {
  [[ -n "${GITHUB_OUTPUT:-}" ]] || { echo "ERROR: GITHUB_OUTPUT not set" >&2; exit 1; }
  [[ -n "${GITHUB_ENV:-}" ]] || { echo "ERROR: GITHUB_ENV not set" >&2; exit 1; }

  {
    echo "project_id=${PROJECT_ID}"
    echo "region=${REGION}"
    echo "workload_identity_provider=${WIF}"
    echo "deploy_service_account=${DEPLOY_SA}"
    echo "gcp_account=${GCP_ACCOUNT}"
    echo "neon_account=${NEON_ACCOUNT}"
    echo "uses_neon=${USES_NEON}"
    echo "neon_org_id=${NEON_ORG_ID}"
    echo "supabase_account=${SUPABASE_ACCOUNT}"
    echo "uses_supabase=${USES_SUPABASE}"
    echo "supabase_org_id=${SUPABASE_ORG_ID}"
  } >> "${GITHUB_OUTPUT}"

  # Workflow commands (add-mask) must go to stdout — never to GITHUB_ENV.
  echo "TF_VAR_project_id=${PROJECT_ID}" >> "${GITHUB_ENV}"
  echo "TF_VAR_region=${REGION}" >> "${GITHUB_ENV}"
  if [[ -n "$NEON_API_KEY" ]]; then
    echo "::add-mask::${NEON_API_KEY}"
    {
      echo "TF_VAR_neon_api_key<<SOPS_NEON_EOF"
      echo "${NEON_API_KEY}"
      echo "SOPS_NEON_EOF"
    } >> "${GITHUB_ENV}"
    echo "TF_VAR_neon_org_id=${NEON_ORG_ID}" >> "${GITHUB_ENV}"
  else
    echo "TF_VAR_neon_api_key=unused" >> "${GITHUB_ENV}"
    echo "TF_VAR_neon_org_id=" >> "${GITHUB_ENV}"
  fi
  if [[ -n "$SUPABASE_ACCESS_TOKEN" ]]; then
    echo "::add-mask::${SUPABASE_ACCESS_TOKEN}"
    {
      echo "TF_VAR_supabase_access_token<<SOPS_SUPABASE_EOF"
      echo "${SUPABASE_ACCESS_TOKEN}"
      echo "SOPS_SUPABASE_EOF"
    } >> "${GITHUB_ENV}"
    echo "TF_VAR_supabase_org_id=${SUPABASE_ORG_ID}" >> "${GITHUB_ENV}"
  else
    echo "TF_VAR_supabase_access_token=unused" >> "${GITHUB_ENV}"
    echo "TF_VAR_supabase_org_id=" >> "${GITHUB_ENV}"
  fi
}

emit_exports() {
  echo "export TF_VAR_project_id=$(printf %q "$PROJECT_ID")"
  echo "export TF_VAR_region=$(printf %q "$REGION")"
  echo "export CLOUD_DEPLOY_WIF=$(printf %q "$WIF")"
  echo "export CLOUD_DEPLOY_SA=$(printf %q "$DEPLOY_SA")"
  if [[ -n "$NEON_API_KEY" ]]; then
    echo "export TF_VAR_neon_api_key=$(printf %q "$NEON_API_KEY")"
    echo "export TF_VAR_neon_org_id=$(printf %q "$NEON_ORG_ID")"
  else
    echo "export TF_VAR_neon_api_key=unused"
  fi
  if [[ -n "$SUPABASE_ACCESS_TOKEN" ]]; then
    echo "export TF_VAR_supabase_access_token=$(printf %q "$SUPABASE_ACCESS_TOKEN")"
    echo "export TF_VAR_supabase_org_id=$(printf %q "$SUPABASE_ORG_ID")"
  else
    echo "export TF_VAR_supabase_access_token=unused"
  fi
}

case "$FORMAT" in
  gha) emit_gha ;;
  exports|*) emit_exports ;;
esac
