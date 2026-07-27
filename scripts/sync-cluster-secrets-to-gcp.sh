#!/usr/bin/env bash
# scripts/sync-cluster-secrets-to-gcp.sh
#
# Read secret material from the Kubernetes cluster (Vault/ESO-sourced secrets
# already materialised as k8s Secrets) and write versions into GCP Secret Manager.
#
# Vault OpenBao is the cluster source of truth via ExternalSecrets; when Vault is
# down, k8s secrets still hold the last synced values. This script never writes
# secret values into the git repo (public-safe).
#
# Prerequisites: kubectl context to the stawi cluster, gcloud auth with secretmanager.admin
# on target projects, yq/jq optional.
#
# Usage:
#   ./scripts/sync-cluster-secrets-to-gcp.sh              # all mapped secrets
#   ./scripts/sync-cluster-secrets-to-gcp.sh --dry-run
#   ./scripts/sync-cluster-secrets-to-gcp.sh --only identity-authentication-google-oauth-client-id
#
set -euo pipefail

DRY_RUN="false"
ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN="true"; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

say()  { printf '\e[1;34m[%s][sync-secrets]\e[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\e[1;33m[%s][sync-secrets]\e[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '\e[1;31m[%s][sync-secrets]\e[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

command -v kubectl >/dev/null || die "kubectl required"
command -v gcloud >/dev/null || die "gcloud required"
command -v python3 >/dev/null || die "python3 required"

# k8s_get_ns secret key -> prints raw secret value to stdout (no trailing newline strip issues)
k8s_get() {
  local ns="$1" secret="$2" key="$3"
  kubectl get secret -n "$ns" "$secret" -o "jsonpath={.data['${key}']}" 2>/dev/null \
    | python3 -c 'import sys,base64; d=sys.stdin.read().strip();
print(base64.b64decode(d).decode("utf-8", errors="replace") if d else "", end="")'
}

ensure_secret() {
  local project="$1" name="$2"
  if gcloud secrets describe "$name" --project="$project" >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    say "DRY-RUN create secret $project/$name"
    return 0
  fi
  say "create secret $project/$name"
  gcloud secrets create "$name" --project="$project" --replication-policy=automatic --quiet
}

add_version() {
  local project="$1" name="$2" value="$3"
  if [[ -z "$value" ]]; then
    warn "skip empty value for $project/$name"
    return 1
  fi
  if [[ -n "$ONLY" && "$name" != "$ONLY" ]]; then
    return 0
  fi
  ensure_secret "$project" "$name"
  if [[ "$DRY_RUN" == "true" ]]; then
    say "DRY-RUN add version $project/$name (len=${#value})"
    return 0
  fi
  # Pipe value via process substitution — never write to repo workspace.
  printf '%s' "$value" | gcloud secrets versions add "$name" \
    --project="$project" \
    --data-file=- \
    --quiet
  say "added version $project/$name (len=${#value})"
}

# ---------------------------------------------------------------------------
# Mapping: (project, sm_secret_id) <- k8s (ns, secret, key)
# Values are Vault-originated where ExternalSecret used vault-backend.
# ---------------------------------------------------------------------------

say "kubectl context: $(kubectl config current-context 2>/dev/null || echo unknown)"
say "Vault/ESO note: ClusterSecretStore may be down; using materialised k8s Secrets"

# --- Identity (stawi-identity) ---
P=stawi-identity

# Google OAuth (Vault: stawi/identity/authentication/service-secrets)
add_version "$P" "identity-authentication-google-oauth-client-id" \
  "$(k8s_get identity google-oauth-credentials client-id)"
add_version "$P" "identity-authentication-google-oauth-client-secret" \
  "$(k8s_get identity google-oauth-credentials client-secret)"

# Session / CSRF (Vault: stawi/identity/authentication/service-secrets)
add_version "$P" "identity-authentication-csrf-secret" \
  "$(k8s_get identity service-authentication-secrets csrf-secret)"
add_version "$P" "identity-authentication-cookie-hash-key" \
  "$(k8s_get identity service-authentication-secrets secure-cookie-hash-key)"
add_version "$P" "identity-authentication-cookie-block-key" \
  "$(k8s_get identity service-authentication-secrets secure-cookie-block-key)"

# Hydra webhook PSK (generator-backed in cluster; shared SM id)
# Prefer plain psk for HYDRA_WEBHOOK_API_PSK / WEBHOOK_BEARER_PSK consumers that add Bearer themselves.
add_version "$P" "hydra-webhook-psk" \
  "$(k8s_get identity hydra-webhook-psk psk)"

# Hydra system/cookie secrets
add_version "$P" "identity-oauth2-hydra-secrets-system" \
  "$(k8s_get identity service-authentication-oauth2-hydra secretsSystem)"
add_version "$P" "identity-oauth2-hydra-secrets-cookie" \
  "$(k8s_get identity service-authentication-oauth2-hydra secretsCookie)"

# Profile DEK material (cluster secret service-profile-dek)
add_version "$P" "identity-profile-dek-aes-key" \
  "$(k8s_get identity service-profile-dek aes-key)"
add_version "$P" "identity-profile-dek-hmac-key" \
  "$(k8s_get identity service-profile-dek hmac-key)"
add_version "$P" "identity-profile-dek-key-id" \
  "$(k8s_get identity service-profile-dek key-id)"

# --- Platform (stawi-platform) ---
P=stawi-platform

# Shared hydra psk for Frame OAuth signer on platform services
add_version "$P" "hydra-webhook-psk" \
  "$(k8s_get platform hydra-webhook-psk psk || k8s_get identity hydra-webhook-psk psk)"

# Files encryption (Vault/cluster)
add_version "$P" "platform-files-encryption-phrase" \
  "$(k8s_get platform service-files-encryption ENCRYPTION_PHRASE)"

# R2/S3 storage (Vault: typically stawi/platform/... cloudflare-r2)
add_version "$P" "platform-files-s3-endpoint" \
  "$(k8s_get platform cloudflare-r2-storage-creds ENDPOINT_URL)"
add_version "$P" "platform-files-s3-access-key-id" \
  "$(k8s_get platform cloudflare-r2-storage-creds ACCESS_KEY_ID)"
add_version "$P" "platform-files-s3-access-key-secret" \
  "$(k8s_get platform cloudflare-r2-storage-creds ACCESS_SECRET_KEY)"

# Cloudflare TURN (Vault: stawi/platform/devices/cloudflare-turn)
add_version "$P" "platform-devices-cloudflare-turn-token-id" \
  "$(k8s_get platform service-devices-cloudflare-turn-secret cf_turn_id)"
add_version "$P" "platform-devices-cloudflare-turn-api-token" \
  "$(k8s_get platform service-devices-cloudflare-turn-secret cf_turn_api_key)"

# --- Operations (stawi-operations if project exists; else identity for cross-read secrets) ---
# Prefer stawi-operations when present; audit may still live on identity project today.
if gcloud projects describe stawi-operations >/dev/null 2>&1; then
  OP=stawi-operations
else
  OP=stawi-identity
  warn "project stawi-operations not accessible; ops secrets go to $OP"
fi

add_version "$OP" "hydra-webhook-psk" \
  "$(k8s_get operations hydra-webhook-psk psk || k8s_get identity hydra-webhook-psk psk)"

add_version "$OP" "audit-signing-key" \
  "$(k8s_get operations audit-signing-key private_key)"

add_version "$OP" "service-files-encryption" \
  "$(k8s_get operations service-files-encryption ENCRYPTION_PHRASE || k8s_get platform service-files-encryption ENCRYPTION_PHRASE)"

add_version "$OP" "operations-redirect-analytics-username" \
  "$(k8s_get operations analytics-credentials-redirect ANALYTICS_USERNAME)"
add_version "$OP" "operations-redirect-analytics-password" \
  "$(k8s_get operations analytics-credentials-redirect ANALYTICS_PASSWORD)"

add_version "$OP" "operations-thesa-analytics-backend-url" \
  "$(k8s_get operations analytics-credentials-thesa ANALYTICS_BACKEND_URL)"
add_version "$OP" "operations-thesa-analytics-token" \
  "$(k8s_get operations analytics-credentials-thesa ANALYTICS_TOKEN)"

# Also seed identity-project audit key if audit is temporarily on stawi-identity
if [[ "$OP" != "stawi-identity" ]]; then
  add_version "stawi-identity" "audit-signing-key" \
    "$(k8s_get operations audit-signing-key private_key)" || true
fi

say "done. Secret values never written to the repository."
say "Next: ensure Terraform always mounts these secret IDs (extra_secret_ids + secret_env_extra),"
say "then re-apply apps or gcloud run services update --update-secrets=..."
