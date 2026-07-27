#!/usr/bin/env bash
# scripts/sync-cluster-secrets-to-gcp.sh
#
# Read secret material from the Kubernetes cluster (Vault/ESO-sourced secrets
# already materialised as k8s Secrets) and write versions into GCP Secret Manager.
#
# Vault OpenBao is the cluster source of truth via ExternalSecrets
# (ClusterSecretStore vault-backend, KV v2 mount `secret`). When Vault is down,
# k8s secrets still hold the last synced values — this script uses those.
# This script never writes secret values into the git repo (public-safe).
#
# Vault skill pattern (when OpenBao pods are Ready):
#   SA_TOKEN=$(kubectl create token external-secrets -n external-secrets --audience=vault --duration=600s)
#   # exec into active openbao pod; bao login with kubernetes role external-secrets
#   # bao kv get -mount=secret stawi/identity/authentication/service-secrets
# Full path map: docs/CLUSTER_ENV_PARITY.md
#
# Prerequisites: kubectl context to the stawi cluster, gcloud auth with secretmanager.admin
# on target projects.
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

# Fetch k8s value only when this secret will be written (honours --only).
sync_one() {
  local project="$1" name="$2" ns="$3" secret="$4" key="$5"
  local alt_ns="${6:-}" alt_secret="${7:-}" alt_key="${8:-}"
  if [[ -n "$ONLY" && "$name" != "$ONLY" ]]; then
    return 0
  fi
  local value
  value="$(k8s_get "$ns" "$secret" "$key")"
  if [[ -z "$value" && -n "$alt_ns" ]]; then
    value="$(k8s_get "$alt_ns" "$alt_secret" "$alt_key")"
  fi
  if [[ -z "$value" ]]; then
    warn "skip empty value for $project/$name (k8s $ns/$secret:$key)"
    return 1
  fi
  ensure_secret "$project" "$name"
  if [[ "$DRY_RUN" == "true" ]]; then
    say "DRY-RUN add version $project/$name (len=${#value})"
    return 0
  fi
  # Pipe value — never write to repo workspace.
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
# Vault: stawi/identity/authentication/service-secrets, oauth2/hydra-secrets, default/dek-keys
P=stawi-identity
sync_one "$P" "identity-authentication-google-oauth-client-id" identity google-oauth-credentials client-id
sync_one "$P" "identity-authentication-google-oauth-client-secret" identity google-oauth-credentials client-secret
sync_one "$P" "identity-authentication-csrf-secret" identity service-authentication-secrets csrf-secret
sync_one "$P" "identity-authentication-cookie-hash-key" identity service-authentication-secrets secure-cookie-hash-key
sync_one "$P" "identity-authentication-cookie-block-key" identity service-authentication-secrets secure-cookie-block-key
# Prefer plain psk (not bearer-psk) for consumers that add Bearer themselves.
sync_one "$P" "hydra-webhook-psk" identity hydra-webhook-psk psk
sync_one "$P" "identity-oauth2-hydra-secrets-system" identity service-authentication-oauth2-hydra secretsSystem
sync_one "$P" "identity-oauth2-hydra-secrets-cookie" identity service-authentication-oauth2-hydra secretsCookie
sync_one "$P" "identity-profile-dek-aes-key" identity service-profile-dek aes-key
sync_one "$P" "identity-profile-dek-hmac-key" identity service-profile-dek hmac-key
sync_one "$P" "identity-profile-dek-key-id" identity service-profile-dek key-id

# --- Platform (stawi-platform) ---
# Vault: stawi/platform/files/r2-credentials, devices/cloudflare-turn
P=stawi-platform
sync_one "$P" "hydra-webhook-psk" platform hydra-webhook-psk psk identity hydra-webhook-psk psk
sync_one "$P" "platform-files-encryption-phrase" platform service-files-encryption ENCRYPTION_PHRASE
sync_one "$P" "platform-files-s3-endpoint" platform cloudflare-r2-storage-creds ENDPOINT_URL
sync_one "$P" "platform-files-s3-access-key-id" platform cloudflare-r2-storage-creds ACCESS_KEY_ID
sync_one "$P" "platform-files-s3-access-key-secret" platform cloudflare-r2-storage-creds ACCESS_SECRET_KEY
sync_one "$P" "platform-devices-cloudflare-turn-token-id" platform service-devices-cloudflare-turn-secret cf_turn_id
sync_one "$P" "platform-devices-cloudflare-turn-api-token" platform service-devices-cloudflare-turn-secret cf_turn_api_key

# --- Operations (prefer stawi-operations; fall back to stawi-identity) ---
# Vault: stawi/operations/audit/signing, thesa/analytics, product-opportunities analytics
if gcloud projects describe stawi-operations >/dev/null 2>&1; then
  OP=stawi-operations
else
  OP=stawi-identity
  warn "project stawi-operations not accessible; ops secrets go to $OP"
fi

sync_one "$OP" "hydra-webhook-psk" operations hydra-webhook-psk psk identity hydra-webhook-psk psk
sync_one "$OP" "audit-signing-key" operations audit-signing-key private_key
sync_one "$OP" "service-files-encryption" operations service-files-encryption ENCRYPTION_PHRASE platform service-files-encryption ENCRYPTION_PHRASE
sync_one "$OP" "operations-redirect-analytics-username" operations analytics-credentials-redirect ANALYTICS_USERNAME
sync_one "$OP" "operations-redirect-analytics-password" operations analytics-credentials-redirect ANALYTICS_PASSWORD
sync_one "$OP" "operations-thesa-analytics-backend-url" operations analytics-credentials-thesa ANALYTICS_BACKEND_URL
sync_one "$OP" "operations-thesa-analytics-token" operations analytics-credentials-thesa ANALYTICS_TOKEN

if [[ "$OP" != "stawi-identity" ]]; then
  sync_one "stawi-identity" "audit-signing-key" operations audit-signing-key private_key || true
fi

say "done. Secret values never written to the repository."
say "Next: ensure Terraform always mounts these secret IDs (extra_secret_ids + secret_env_extra),"
say "then re-apply apps or gcloud run services update --update-secrets=..."
