#!/usr/bin/env bash
# scripts/seed-gcp-secrets.sh
#
# Copy secret values into GCP Secret Manager for a cloud.deployment app/env.
# Does not put secrets in git. Safe to re-run (adds new secret versions).
#
# Usage:
#   # From KEY=value file (chmod 600 recommended)
#   ./scripts/seed-gcp-secrets.sh \
#     --app identity-authentication \
#     --env stawi-prod \
#     --from-env-file ./secrets.identity.local.env
#
#   # Single secret
#   ./scripts/seed-gcp-secrets.sh --project stawi-identity \
#     --set neon-org-api-key="$NEON_ORG_API_KEY"
#
#   # Neon org key from SOPS (operator with private age key)
#   ./scripts/seed-gcp-secrets.sh --env stawi-prod --app identity-authentication \
#     --from-sops-neon identity
#
#   # Generate random values for empty keys listed in catalog (print once)
#   ./scripts/seed-gcp-secrets.sh --app identity-oauth2-hydra --env stawi-prod \
#     --generate-missing --from-env-file ./secrets.partial.env
#
# Env file format (lines KEY=value; # comments ok):
#   neon-org-api-key=napi_...
#   hydra-webhook-psk=...
#   identity-authentication-csrf-secret=...
#
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"

APP=""
ENV_NAME="stawi-prod"
PROJECT=""
FROM_FILE=""
FROM_SOPS_NEON=""
GENERATE_MISSING="false"
DRY_RUN="false"
CATALOG=""
ROOT=""
SET_PAIRS=()

say()  { printf '\e[1;34m[%s][secrets]\e[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\e[1;33m[%s][secrets]\e[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '\e[1;31m[%s][secrets]\e[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --env) ENV_NAME="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --from-env-file) FROM_FILE="$2"; shift 2 ;;
    --from-sops-neon) FROM_SOPS_NEON="$2"; shift 2 ;;
    --generate-missing) GENERATE_MISSING="true"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --catalog) CATALOG="$2"; shift 2 ;;
    --set)
      # --set id=value
      SET_PAIRS+=("$2"); shift 2 ;;
    -h|--help) usage ;;
    *) die "unknown arg: $1" ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="${CATALOG:-$ROOT/config/secret-catalog/identity.yaml}"

command -v gcloud >/dev/null 2>&1 || die "gcloud required"
command -v yq >/dev/null 2>&1 || die "yq required"

if [[ -z "$PROJECT" ]]; then
  [[ -n "$APP" ]] || die "pass --app or --project"
  command -v jq >/dev/null 2>&1 || die "jq required for resolve"
  PROJECT=$(
    "$ROOT/.github/scripts/resolve-app-context.sh" "$APP" "$ENV_NAME" --format=json \
      | jq -r '.project_id'
  )
fi
[[ -n "$PROJECT" && "$PROJECT" != "null" ]] || die "could not resolve project_id"

say "project=$PROJECT app=${APP:-all} env=$ENV_NAME"

declare -A VALUES=()

load_env_file() {
  local f="$1" line key val
  [[ -f "$f" ]] || die "env file not found: $f"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^([A-Za-z0-9_.-]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      # strip optional surrounding quotes
      val="${val%\"}"; val="${val#\"}"
      val="${val%\'}"; val="${val#\'}"
      VALUES["$key"]="$val"
    fi
  done <"$f"
}

if [[ -n "$FROM_FILE" ]]; then
  load_env_file "$FROM_FILE"
fi

for pair in "${SET_PAIRS[@]:-}"; do
  [[ "$pair" == *=* ]] || die "bad --set $pair (want id=value)"
  VALUES["${pair%%=*}"]="${pair#*=}"
done

if [[ -n "$FROM_SOPS_NEON" ]]; then
  command -v sops >/dev/null 2>&1 || die "sops required for --from-sops-neon"
  sops_path="$ROOT/credentials/neon/${FROM_SOPS_NEON}/auth.yaml"
  [[ -f "$sops_path" ]] || die "missing $sops_path"
  key=$(sops -d "$sops_path" | yq -r '.auth.api_key // empty')
  [[ -n "$key" && "$key" != "null" ]] || die "no auth.api_key in decrypted sops"
  VALUES["neon-org-api-key"]="$key"
  say "loaded neon-org-api-key from sops ($sops_path)"
fi

# Collect required secret IDs from catalog for this app
REQUIRED_IDS=()
if [[ -n "$APP" && -f "$CATALOG" ]]; then
  while IFS= read -r id; do
    [[ -n "$id" && "$id" != "null" ]] && REQUIRED_IDS+=("$id")
  done < <(yq -r "
    .deploy_time[].id,
    .shared[].id,
    .apps[\"${APP}\"].runtime_secrets[]? | select(.managed_by_tofu != true) | .id
  " "$CATALOG" 2>/dev/null || true)
  # Always include deploy-time neon key when seeding identity domain
  REQUIRED_IDS+=("neon-org-api-key")
fi

# Deduplicate
if [[ ${#REQUIRED_IDS[@]} -gt 0 ]]; then
  mapfile -t REQUIRED_IDS < <(printf '%s\n' "${REQUIRED_IDS[@]}" | sort -u)
fi

if [[ "$GENERATE_MISSING" == "true" ]]; then
  for id in "${REQUIRED_IDS[@]:-}"; do
    if [[ -z "${VALUES[$id]:-}" ]]; then
      # skip database urls
      [[ "$id" == *database-url* ]] && continue
      VALUES["$id"]="$(openssl rand -base64 48 | tr -d '\n')"
      say "generated random value for $id"
    fi
  done
fi

if [[ ${#VALUES[@]} -eq 0 ]]; then
  die "no secret values to seed — use --from-env-file, --set, --from-sops-neon, and/or --generate-missing"
fi

upsert_secret() {
  local id="$1" value="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    say "DRY-RUN would upsert secret=$id project=$PROJECT (len=${#value})"
    return 0
  fi
  if gcloud secrets describe "$id" --project="$PROJECT" >/dev/null 2>&1; then
    printf '%s' "$value" | gcloud secrets versions add "$id" \
      --project="$PROJECT" --data-file=- --quiet
    say "added version: $id"
  else
    printf '%s' "$value" | gcloud secrets create "$id" \
      --project="$PROJECT" \
      --replication-policy=automatic \
      --data-file=- --quiet
    say "created: $id"
  fi
  # Grant deploy SA accessor if we can resolve it
  local sa
  sa=$(yq -r ".accounts.identity.envs[\"${ENV_NAME}\"].deploy_service_account // empty" \
    "$ROOT/config/gcp-accounts.yaml" 2>/dev/null || true)
  if [[ -n "$sa" && "$sa" != "null" ]]; then
    gcloud secrets add-iam-policy-binding "$id" \
      --project="$PROJECT" \
      --member="serviceAccount:${sa}" \
      --role="roles/secretmanager.secretAccessor" \
      --quiet >/dev/null 2>&1 || true
  fi
}

# If DECLARED_ONLY / app set: only seed keys that are either in VALUES and in required list, or all VALUES
for id in "${!VALUES[@]}"; do
  upsert_secret "$id" "${VALUES[$id]}"
done

say ""
say "Done. Seeded ${#VALUES[@]} secret(s) into project $PROJECT"
say "Verify: gcloud secrets list --project=$PROJECT"
if [[ -n "$APP" ]]; then
  say "Next: trigger app-plan/app-apply for $APP / $ENV_NAME"
fi
