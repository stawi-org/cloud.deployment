#!/usr/bin/env bash
# scripts/bootstrap-gcp-account.sh
#
# Idempotently configure a GCP project for cloud.deployment (Cloud Run +
# Pub/Sub + Secret Manager), then open a PR that:
#   1) updates config/gcp-accounts.yaml with project/WIF/SA (non-secret registry)
#   2) stores a SOPS-encrypted credentials/gcp/<account>/<env>/auth.yaml
#      (same age recipient pattern as deployment.infra)
#
# Architecture stays intact: apps still select gcp.account + neon.account in
# app.yaml; CI resolves context via resolve-app-context.sh; runtime secrets
# stay in Secret Manager.
#
#   GitHub JWT  →  WIF pool/provider (github / github-actions)
#                       ↓ attribute.repository == stawi-org/cloud.deployment
#                  SA tofu-deploy@PROJECT  (roles/iam.workloadIdentityUser)
#                       ↓ impersonation
#                  OpenTofu plan/apply for apps bound to this account
#
# ── SAFETY ───────────────────────────────────────────────────────────────
# Safe to re-run. Does NOT delete projects, Cloud Run services, or secrets.
# Only ensures APIs, WIF, SA, and IAM bindings.
#
# Cloud Shell (upload only this script, or curl from main):
#   export GITHUB_TOKEN=ghp_xxx   # repo scope recommended
#   ./bootstrap-gcp-account.sh \
#     --project stawi-identity-dev \
#     --account identity \
#     --env stawi-dev \
#     --region europe-west1
#
# Neon is independent of GCP. Do NOT pass Neon keys here.
# Create Neon orgs/API keys separately; apps link them only via app.yaml
# (neon.account) and config/neon-accounts.yaml. CI loads Neon credentials
# from wherever that registry points (e.g. Secret Manager or GH Environment).
#
# Encryption uses the public age key in .sops.yaml — no private age key
# is required on the bootstrap machine.
#
set -euo pipefail

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS="${GIT_ASKPASS:-/bin/true}"
export SSH_ASKPASS="${SSH_ASKPASS:-/bin/true}"
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new}"
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=credential.helper
export GIT_CONFIG_VALUE_0=
export PATH="${HOME}/.local/bin:${PATH}"

# -------- defaults --------
PROJECT=""
ACCOUNT=""          # config/gcp-accounts.yaml key (identity, payments, …)
ENV_NAME="stawi-dev"
REGION="europe-west1"
REPO_PATH=""
BASE_BRANCH="main"
BRANCH=""
NO_PUSH="false"
NO_PR="false"
NO_CLONE="false"
IAM_ONLY="false"
FORCE_REPO_WRITE="false"

WIF_POOL="github"
WIF_PROVIDER="github-actions"
SA_ID="tofu-deploy"
GITHUB_REPO="stawi-org/cloud.deployment"
OIDC_ISSUER="https://token.actions.githubusercontent.com"
ATTR_CONDITION="assertion.repository=='${GITHUB_REPO}'"
ATTR_MAPPING="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref"

SOPS_VERSION="v3.11.0"
CLONE_URL="https://github.com/${GITHUB_REPO}.git"
DEFAULT_CLONE_DIR="${HOME}/cloud.deployment"

usage() {
  if [[ -n "${BASH_SOURCE[0]:-}" && -r "${BASH_SOURCE[0]}" ]]; then
    awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' \
      "${BASH_SOURCE[0]}"
  fi
  cat <<'EOF'

Flags:
  --project <ID>         GCP project id (required)
  --account <KEY>        gcp-accounts.yaml account key (required)
                         e.g. identity | payments | notifications | platform | labs
  --env <NAME>           stawi-dev | stawi-prod (default: stawi-dev)
  --region <REGION>      Default europe-west1
  --repo-path <PATH>     cloud.deployment checkout (default: auto-clone ~/cloud.deployment)
  --no-clone             Fail if no checkout found
  --base-branch <NAME>   Default main
  --branch <NAME>        Push branch (default: onboard-gcp-<account>-<env>)
  --no-push              Commit only; skip push
  --no-pr                Push but do not open PR
  --iam-only             GCP only; never write git
  --force-repo-write     Rewrite registry/auth PR even if already present
  -h, --help

Cloud Shell:
  export GITHUB_TOKEN=ghp_xxx
  ./bootstrap-gcp-account.sh --project P --account identity --env stawi-dev
EOF
  exit 1
}

say()  { printf '\e[1;34m[%s][%s]\e[0m %s\n' "$(date +%H:%M:%S)" "${PROJECT:-gcp}" "$*"; }
warn() { printf '\e[1;33m[%s][%s]\e[0m %s\n' "$(date +%H:%M:%S)" "${PROJECT:-gcp}" "$*" >&2; }
die()  { printf '\e[1;31m[%s][%s]\e[0m %s\n' "$(date +%H:%M:%S)" "${PROJECT:-gcp}" "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)          PROJECT="$2"; shift 2 ;;
    --account)          ACCOUNT="$2"; shift 2 ;;
    --env)              ENV_NAME="$2"; shift 2 ;;
    --region)           REGION="$2"; shift 2 ;;
    --neon-api-key|--neon-org-api-key)
      die "Neon is not part of GCP bootstrap. Create Neon orgs/keys separately; link via app.yaml neon.account only."
      ;;
    --repo-path)        REPO_PATH="$2"; shift 2 ;;
    --base-branch)      BASE_BRANCH="$2"; shift 2 ;;
    --branch)           BRANCH="$2"; shift 2 ;;
    --no-push)          NO_PUSH="true"; shift ;;
    --no-pr)            NO_PR="true"; shift ;;
    --no-clone)         NO_CLONE="true"; shift ;;
    --iam-only)         IAM_ONLY="true"; shift ;;
    --force-repo-write) FORCE_REPO_WRITE="true"; shift ;;
    -h|--help)          usage ;;
    *)                  echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$PROJECT" ]] || die "--project is required"
[[ -n "$ACCOUNT" ]] || die "--account is required (e.g. identity)"
case "$ENV_NAME" in
  stawi-dev|stawi-prod) ;;
  *) die "--env must be stawi-dev or stawi-prod (got: $ENV_NAME)" ;;
esac
if [[ "$ACCOUNT" == *"/"* || "$ACCOUNT" == *".."* ]]; then
  die "--account must be a single path segment"
fi

BRANCH="${BRANCH:-onboard-gcp-${ACCOUNT}-${ENV_NAME}}"
SA_EMAIL="${SA_ID}@${PROJECT}.iam.gserviceaccount.com"

# -------- helpers (mirrors deployment.infra bootstrap style) --------
ensure_sops() {
  if command -v sops >/dev/null 2>&1; then
    return 0
  fi
  local dest="${HOME}/.local/bin" arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "unsupported arch for sops: $arch" ;;
  esac
  mkdir -p "$dest"
  say "installing sops ${SOPS_VERSION} → ${dest}/sops"
  curl -fsSL -o "${dest}/sops" \
    "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${arch}"
  chmod +x "${dest}/sops"
  export PATH="${dest}:${PATH}"
  command -v sops >/dev/null 2>&1 || die "failed to install sops"
}

github_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then printf '%s' "$GITHUB_TOKEN"; return 0; fi
  if [[ -n "${GH_TOKEN:-}" ]]; then printf '%s' "$GH_TOKEN"; return 0; fi
  if command -v gh >/dev/null 2>&1; then
    local t
    t=$(GH_PROMPT_DISABLED=1 gh auth token 2>/dev/null || true)
    [[ -n "$t" ]] && { printf '%s' "$t"; return 0; }
  fi
  return 1
}

github_login() {
  local token="${1:-}"
  [[ -n "$token" ]] || return 1
  curl -fsS -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/user" 2>/dev/null \
    | jq -r '.login // empty'
}

github_ensure_fork() {
  local token="$1" login fork_full
  login=$(github_login "$token") || true
  [[ -n "$login" ]] || return 1
  fork_full="${login}/${GITHUB_REPO#*/}"
  if curl -fsS -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${token}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${fork_full}" 2>/dev/null | grep -qx '200'; then
    printf '%s' "$fork_full"
    return 0
  fi
  say "creating fork ${fork_full}"
  local code
  code=$(curl -sS -o /tmp/cd-fork.json -w '%{http_code}' -X POST \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${GITHUB_REPO}/forks" || true)
  if [[ "$code" != "202" && "$code" != "200" ]]; then
    warn "fork create HTTP ${code}"
    return 1
  fi
  local i
  for ((i = 1; i <= 30; i++)); do
    if curl -fsS -o /dev/null -H "Authorization: Bearer ${token}" \
        "https://api.github.com/repos/${fork_full}" 2>/dev/null; then
      printf '%s' "$fork_full"
      return 0
    fi
    sleep 2
  done
  return 1
}

git_push_noninteractive() {
  local url="$1" refspec="$2"
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true \
    git -c credential.helper= -c core.askPass=/bin/true \
      push --porcelain "$url" "$refspec" 2>/tmp/cd-git-push.err
}

github_api() {
  local method="$1" path="$2"
  shift 2
  local token
  token="$(github_token)" || die "GITHUB_TOKEN required for GitHub API"
  curl -fsS -X "$method" \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com${path}" \
    "$@"
}

github_create_pr() {
  local title="$1" head="$2" base="$3" body="$4"
  local payload resp code body_json pr_url
  payload=$(jq -n --arg title "$title" --arg head "$head" --arg base "$base" --arg body "$body" \
    '{title:$title, head:$head, base:$base, body:$body}')
  resp=$(curl -sS -X POST \
    -H "Authorization: Bearer $(github_token)" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "https://api.github.com/repos/${GITHUB_REPO}/pulls" \
    -w '\n%{http_code}')
  code=$(printf '%s\n' "$resp" | tail -1)
  body_json=$(printf '%s\n' "$resp" | sed '$d')
  if [[ "$code" == "201" ]]; then
    pr_url=$(jq -r '.html_url // empty' <<<"$body_json")
    say "opened PR: $pr_url"
    printf '%s\n' "$pr_url"
    return 0
  fi
  if [[ "$code" == "422" ]]; then
    local head_q existing
    if [[ "$head" == *:* ]]; then head_q="$head"; else head_q="${GITHUB_REPO%%/*}:${head}"; fi
    existing=$(github_api GET "/repos/${GITHUB_REPO}/pulls?head=${head_q}&state=open" || true)
    pr_url=$(jq -r '.[0].html_url // empty' <<<"$existing")
    if [[ -n "$pr_url" ]]; then
      say "PR already open: $pr_url"
      printf '%s\n' "$pr_url"
      return 0
    fi
  fi
  warn "create PR failed (HTTP ${code})"
  printf '%s\n' "$body_json" | head -c 600 >&2
  return 1
}

ensure_git_clone() {
  local dest="$1"
  if [[ -d "$dest/.git" && -f "$dest/config/gcp-accounts.yaml" ]]; then
    say "reusing clone at $dest"
    git -C "$dest" fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true
    git -C "$dest" checkout "$BASE_BRANCH" --quiet 2>/dev/null \
      || git -C "$dest" checkout -B "$BASE_BRANCH" "origin/${BASE_BRANCH}" --quiet 2>/dev/null || true
    git -C "$dest" pull --ff-only origin "$BASE_BRANCH" --quiet 2>/dev/null || true
    return 0
  fi
  if [[ -e "$dest" && ! -d "$dest/.git" ]]; then
    die "$dest exists but is not a git clone"
  fi
  say "cloning ${CLONE_URL} → ${dest}"
  mkdir -p "$(dirname "$dest")"
  git clone --branch "$BASE_BRANCH" --single-branch "$CLONE_URL" "$dest" \
    || git clone "$CLONE_URL" "$dest" \
    || die "git clone failed"
}

resolve_repo_path() {
  if [[ -n "$REPO_PATH" ]]; then
    if [[ ! -f "$REPO_PATH/config/gcp-accounts.yaml" ]]; then
      [[ "$NO_CLONE" == "true" ]] && die "--repo-path not a cloud.deployment checkout"
      ensure_git_clone "$REPO_PATH"
    fi
  else
    local detected
    detected=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$detected" && -f "$detected/config/gcp-accounts.yaml" ]]; then
      REPO_PATH="$detected"
      say "using checkout: $REPO_PATH"
    elif [[ "$NO_CLONE" == "true" ]]; then
      die "not in cloud.deployment checkout and --no-clone set"
    else
      REPO_PATH="$DEFAULT_CLONE_DIR"
      ensure_git_clone "$REPO_PATH"
    fi
  fi
  REPO_PATH="$(cd "$REPO_PATH" && pwd)"
  [[ -f "$REPO_PATH/config/gcp-accounts.yaml" ]] || die "missing config/gcp-accounts.yaml"
  [[ -f "$REPO_PATH/.sops.yaml" ]] || die "missing .sops.yaml — wrong checkout?"
  say "repo path: $REPO_PATH"
}

verify_gcloud_access() {
  command -v gcloud >/dev/null 2>&1 || die "missing: gcloud (use GCP Cloud Shell)"
  if ! gcloud projects describe "$PROJECT" --format='value(projectId)' >/dev/null 2>&1; then
    die "cannot describe project ${PROJECT} — gcloud auth login / check permissions"
  fi
  say "gcloud project access: ok ($PROJECT)"
}

compare_pr_url() {
  local base="$1" head="$2"
  printf 'https://github.com/%s/compare/%s...%s?expand=1' "$GITHUB_REPO" "$base" "$head"
}

ensure_iam_binding() {
  # ensure_iam_binding ROLE MEMBER
  local role="$1" member="$2"
  if gcloud projects get-iam-policy "$PROJECT" --format=json 2>/dev/null \
      | jq -e --arg r "$role" --arg m "$member" \
        '.bindings[]? | select(.role==$r) | .members[]? | select(.==$m)' >/dev/null 2>&1; then
    return 0
  fi
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="$member" \
    --role="$role" \
    --condition=None \
    --quiet >/dev/null
}

# -------- prereqs --------
ensure_sops
for cmd in gcloud jq curl python3 git sops; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing: $cmd"
done

resolve_repo_path
verify_gcloud_access

# Validate account/env exist in registry (structure must be planned)
if ! command -v yq >/dev/null 2>&1; then
  # minimal yq install for Cloud Shell
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "unsupported arch for yq: $arch" ;;
  esac
  mkdir -p "${HOME}/.local/bin"
  curl -fsSL -o "${HOME}/.local/bin/yq" \
    "https://github.com/mikefarah/yq/releases/download/v4.44.6/yq_linux_${arch}"
  chmod +x "${HOME}/.local/bin/yq"
  export PATH="${HOME}/.local/bin:${PATH}"
fi
command -v yq >/dev/null 2>&1 || die "yq required"

if ! yq -e ".accounts[\"${ACCOUNT}\"]" "$REPO_PATH/config/gcp-accounts.yaml" >/dev/null 2>&1; then
  die "account '${ACCOUNT}' not in config/gcp-accounts.yaml — add the key to the plan/registry first"
fi
if ! yq -e ".accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"]" "$REPO_PATH/config/gcp-accounts.yaml" >/dev/null 2>&1; then
  die "account '${ACCOUNT}' has no env slice '${ENV_NAME}' in gcp-accounts.yaml"
fi

# =========================================================================
# 1. Enable APIs (Cloud Run stack)
# =========================================================================
say "Enabling APIs on $PROJECT"
gcloud services enable \
  run.googleapis.com \
  secretmanager.googleapis.com \
  pubsub.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  sts.googleapis.com \
  artifactregistry.googleapis.com \
  --project="$PROJECT" \
  --quiet

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
[[ -n "$PROJECT_NUMBER" ]] || die "could not resolve project number"
say "  project number: $PROJECT_NUMBER"

# =========================================================================
# 2. WIF pool + OIDC provider (bound to cloud.deployment)
# =========================================================================
say "Ensuring WIF pool '$WIF_POOL'"
if ! gcloud iam workload-identity-pools describe "$WIF_POOL" \
    --project="$PROJECT" --location=global --format='value(name)' >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$WIF_POOL" \
    --project="$PROJECT" --location=global \
    --display-name="GitHub" \
    --quiet
  say "  pool created"
else
  say "  pool exists"
fi

say "Ensuring OIDC provider '$WIF_PROVIDER' (repo=${GITHUB_REPO})"
if gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER" \
    --project="$PROJECT" --location=global \
    --workload-identity-pool="$WIF_POOL" \
    --format='value(name)' >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers update-oidc "$WIF_PROVIDER" \
    --project="$PROJECT" --location=global \
    --workload-identity-pool="$WIF_POOL" \
    --issuer-uri="$OIDC_ISSUER" \
    --attribute-mapping="$ATTR_MAPPING" \
    --attribute-condition="$ATTR_CONDITION" \
    --quiet 2>/dev/null || true
  say "  provider ensured"
else
  gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER" \
    --project="$PROJECT" --location=global \
    --workload-identity-pool="$WIF_POOL" \
    --display-name="GitHub Actions" \
    --issuer-uri="$OIDC_ISSUER" \
    --attribute-mapping="$ATTR_MAPPING" \
    --attribute-condition="$ATTR_CONDITION" \
    --quiet
  say "  provider created"
fi

WIF_PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/providers/${WIF_PROVIDER}"
say "  WIF: $WIF_PROVIDER_RESOURCE"

# =========================================================================
# 3. Deploy SA + roles + WIF binding
# =========================================================================
say "Ensuring service account $SA_EMAIL"
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_ID" \
    --project="$PROJECT" \
    --display-name="cloud.deployment OpenTofu deploy" \
    --quiet
  # IAM propagation
  for ((i=1; i<=20; i++)); do
    gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" >/dev/null 2>&1 && break
    sleep 2
  done
  sleep 3
  say "  SA created"
else
  say "  SA exists"
fi

say "Ensuring project IAM roles on deploy SA"
for role in \
  roles/run.admin \
  roles/secretmanager.admin \
  roles/pubsub.admin \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountUser \
  roles/storage.objectViewer \
  roles/serviceusage.serviceUsageConsumer
do
  ensure_iam_binding "$role" "serviceAccount:${SA_EMAIL}" || warn "could not bind $role"
  say "  $role"
done

# Allow GitHub OIDC to impersonate deploy SA
WIF_MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/attribute.repository/${GITHUB_REPO}"
say "Ensuring WIF → SA binding"
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="$WIF_MEMBER" \
  --quiet >/dev/null 2>&1 || true
say "  workloadIdentityUser for ${GITHUB_REPO}"

say ""
say "=========================================================="
say "GCP ready for cloud.deployment account=${ACCOUNT} env=${ENV_NAME}"
say "  project: $PROJECT ($PROJECT_NUMBER)"
say "  SA:      $SA_EMAIL"
say "  WIF:     $WIF_PROVIDER_RESOURCE"
say "  SAFETY:  no Cloud Run services deleted; IAM is additive only"
say "  Neon:    not configured here (independent; link per app via neon.account)"

if [[ "$IAM_ONLY" == "true" ]]; then
  say "--iam-only: skipping git/PR"
  exit 0
fi

# =========================================================================
# 5. Repo write: update registry + SOPS auth (worktree)
# =========================================================================
AUTH_REL="credentials/gcp/${ACCOUNT}/${ENV_NAME}/auth.yaml"
already="false"
if git -C "$REPO_PATH" rev-parse --verify "origin/${BASE_BRANCH}" >/dev/null 2>&1 \
    || git -C "$REPO_PATH" fetch origin "$BASE_BRANCH" --quiet 2>/dev/null; then
  if git -C "$REPO_PATH" cat-file -e "origin/${BASE_BRANCH}:${AUTH_REL}" 2>/dev/null; then
    # Check registry already has non-placeholder project
    cur_pid=$(git -C "$REPO_PATH" show "origin/${BASE_BRANCH}:config/gcp-accounts.yaml" 2>/dev/null \
      | yq -r ".accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].project_id // \"\"" 2>/dev/null || true)
    if [[ "$cur_pid" == "$PROJECT" ]]; then
      already="true"
    fi
  fi
fi

if [[ "$already" == "true" && "$FORCE_REPO_WRITE" != "true" ]]; then
  say "already onboarded on origin/${BASE_BRANCH} (${AUTH_REL} + project_id match)"
  say "use --force-repo-write to refresh auth/registry PR"
  exit 0
fi

WORKTREE="${REPO_PATH}/.worktrees/${BRANCH}"
rm -rf "$WORKTREE" 2>/dev/null || true
git -C "$REPO_PATH" fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true
if git -C "$REPO_PATH" show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  git -C "$REPO_PATH" branch -D "$BRANCH" >/dev/null 2>&1 || true
fi
git -C "$REPO_PATH" worktree prune 2>/dev/null || true
git -C "$REPO_PATH" worktree add -b "$BRANCH" "$WORKTREE" "origin/${BASE_BRANCH}" 2>/dev/null \
  || git -C "$REPO_PATH" worktree add -b "$BRANCH" "$WORKTREE" "$BASE_BRANCH" \
  || die "could not create worktree"

say "worktree: $WORKTREE"

# --- Update gcp-accounts.yaml (public registry — plan intact) ---
python3 - "$WORKTREE/config/gcp-accounts.yaml" "$ACCOUNT" "$ENV_NAME" "$PROJECT" "$REGION" \
  "$WIF_PROVIDER_RESOURCE" "$SA_EMAIL" <<'PY'
import sys
from pathlib import Path

path, account, env, project, region, wif, sa = sys.argv[1:8]
try:
    import yaml
except ImportError:
    # minimal fallback without PyYAML: use yq externally — parent should have yq
    sys.exit(0)

text = Path(path).read_text()
data = yaml.safe_load(text)
acc = data.setdefault("accounts", {}).setdefault(account, {})
envs = acc.setdefault("envs", {})
slice_ = envs.setdefault(env, {})
slice_["project_id"] = project
slice_["region"] = region
slice_["workload_identity_provider"] = wif
slice_["deploy_service_account"] = sa
slice_.setdefault("github_environment", f"gcp-{account}-{env.replace('stawi-', '')}" if False else f"gcp-{account}-{env}")
# Prefer stable naming: gcp-identity-dev style already in file
if "github_environment" not in slice_ or not slice_["github_environment"]:
    slice_["github_environment"] = f"gcp-{account}-{env}"
labels = slice_.setdefault("labels", {})
labels.setdefault("managed-by", "cloud-deployment")
labels.setdefault("domain", account)
if env == "stawi-dev":
    labels["environment"] = "dev"
elif env == "stawi-prod":
    labels["environment"] = "prod"

# Keep github_environment from original if present and looks intentional
# (we don't overwrite if already set to non-empty custom)
Path(path).write_text(yaml.safe_dump(data, sort_keys=False, default_flow_style=False))
print(f"updated {path} accounts.{account}.envs.{env}")
PY

# Prefer yq for reliable edit (works without PyYAML)
yq -i "
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].project_id = \"${PROJECT}\" |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].region = \"${REGION}\" |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].workload_identity_provider = \"${WIF_PROVIDER_RESOURCE}\" |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].deploy_service_account = \"${SA_EMAIL}\"
" "$WORKTREE/config/gcp-accounts.yaml"
say "updated config/gcp-accounts.yaml → ${ACCOUNT}/${ENV_NAME}"

# --- SOPS-encrypted auth (like deployment.infra) ---
mkdir -p "$WORKTREE/credentials/gcp/${ACCOUNT}/${ENV_NAME}"
AUTH_PLAIN=$(mktemp)
AUTH_FILE="$WORKTREE/${AUTH_REL}"
cat >"$AUTH_PLAIN" <<EOF
auth:
  account_key: ${ACCOUNT}
  env: ${ENV_NAME}
  project_id: ${PROJECT}
  project_number: "${PROJECT_NUMBER}"
  region: ${REGION}
  workload_identity_provider: ${WIF_PROVIDER_RESOURCE}
  deploy_service_account: ${SA_EMAIL}
  github_repository: ${GITHUB_REPO}
  bootstrapped_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

# --filename: sops matches creation_rules on the intended repo path, not /tmp
(
  cd "$WORKTREE"
  sops -e --filename "$AUTH_REL" "$AUTH_PLAIN" >"$AUTH_FILE"
)
rm -f "$AUTH_PLAIN"
if ! grep -q '^sops:' "$AUTH_FILE"; then
  die "auth.yaml does not look SOPS-encrypted"
fi
say "wrote encrypted $AUTH_REL"

# credentials README
mkdir -p "$WORKTREE/credentials"
cat >"$WORKTREE/credentials/README.md" <<'EOF'
# Encrypted credentials

SOPS-encrypted GCP bootstrap metadata (age recipient in repo `.sops.yaml`).

- Path: `credentials/gcp/<account>/<env>/auth.yaml`
- Written by `scripts/bootstrap-gcp-account.sh` (GCP only — no Neon)
- Public registry remains `config/gcp-accounts.yaml` (project/WIF for CI resolve)
- Runtime secrets (DATABASE_URL, etc.) live in **GCP Secret Manager**, not here
- Neon orgs/keys are independent of GCP bootstrap; apps set neon.account separately

Decrypt (operators with private age key only):

```bash
sops -d credentials/gcp/identity/stawi-dev/auth.yaml
```
EOF

# Commit
cd "$WORKTREE"
if ! git config user.email >/dev/null 2>&1; then
  git config user.email "${GIT_AUTHOR_EMAIL:-bootstrap-gcp@stawi.org}"
fi
if ! git config user.name >/dev/null 2>&1; then
  git config user.name "${GIT_AUTHOR_NAME:-bootstrap-gcp-account}"
fi

git add \
  "config/gcp-accounts.yaml" \
  "$AUTH_REL" \
  "credentials/README.md" \
  ".sops.yaml" 2>/dev/null || true

if git diff --cached --quiet; then
  say "no changes to commit"
else
  git commit -m "onboard gcp ${ACCOUNT}/${ENV_NAME}: registry + SOPS auth for ${PROJECT}"
  say "committed on $BRANCH"
fi

OPEN_URL=$(compare_pr_url "$BASE_BRANCH" "$BRANCH")
PR_HEAD="$BRANCH"
PUSH_OK="false"
TOKEN=$(github_token 2>/dev/null || true)

pr_body_text() {
  cat <<EOF
## Onboard GCP account \`${ACCOUNT}\` / \`${ENV_NAME}\`

Configures cloud.deployment multi-account platform for this GCP project.

| Field | Value |
|-------|--------|
| gcp.account | \`${ACCOUNT}\` |
| env | \`${ENV_NAME}\` |
| project_id | \`${PROJECT}\` |
| region | \`${REGION}\` |
| deploy SA | \`${SA_EMAIL}\` |
| WIF provider | \`${WIF_PROVIDER_RESOURCE}\` |
| SOPS auth | \`${AUTH_REL}\` |

### After merge

1. Apps with \`gcp.account: ${ACCOUNT}\` resolve to this project via \`resolve-app-context.sh\`.
2. CI uses WIF → \`${SA_EMAIL}\` for plan/apply.
3. Runtime secrets remain in Secret Manager (not git).
4. Neon is separate: create Neon orgs/keys out-of-band; apps set \`neon.account\` independently.

Architecture docs unchanged: multi-account + SM + path-filtered CI.
EOF
}

if [[ "$NO_PUSH" == "true" ]]; then
  say "skipping push (--no-push)"
  say "OPEN: $OPEN_URL"
  exit 0
fi

REFSPEC="HEAD:refs/heads/${BRANCH}"
if [[ -n "$TOKEN" ]]; then
  say "pushing with GitHub token"
  token_url="https://x-access-token:${TOKEN}@github.com/${GITHUB_REPO}.git"
  if git_push_noninteractive "$token_url" "$REFSPEC"; then
    PUSH_OK="true"
    say "pushed origin/${BRANCH}"
  else
    warn "push to ${GITHUB_REPO} failed"
    head -c 300 /tmp/cd-git-push.err >&2 || true
    if fork_full=$(github_ensure_fork "$TOKEN"); then
      fork_url="https://x-access-token:${TOKEN}@github.com/${fork_full}.git"
      if git_push_noninteractive "$fork_url" "$REFSPEC"; then
        PUSH_OK="true"
        PR_HEAD="${fork_full%%/*}:${BRANCH}"
        OPEN_URL="https://github.com/${GITHUB_REPO}/compare/${BASE_BRANCH}...${PR_HEAD}?expand=1"
        say "pushed fork ${fork_full}"
      fi
    fi
  fi
else
  if git_push_noninteractive "https://github.com/${GITHUB_REPO}.git" "$REFSPEC" \
      || git_push_noninteractive "origin" "$REFSPEC"; then
    PUSH_OK="true"
  fi
fi

if [[ "$PUSH_OK" != "true" ]]; then
  cat <<EOF

GCP is complete. Git push needs a token:

  export GITHUB_TOKEN=ghp_xxxxxxxx
  ./bootstrap-gcp-account.sh --project ${PROJECT} --account ${ACCOUNT} --env ${ENV_NAME} --region ${REGION}

Local branch: ${BRANCH} in worktree ${WORKTREE}
EOF
  exit 0
fi

if [[ "$NO_PR" != "true" && -n "$TOKEN" ]]; then
  if pr_url=$(github_create_pr \
    "onboard gcp ${ACCOUNT}/${ENV_NAME}" \
    "$PR_HEAD" \
    "$BASE_BRANCH" \
    "$(pr_body_text)"); then
    [[ -n "$pr_url" ]] && OPEN_URL="$pr_url"
  fi
fi

say ""
say "Done."
say "  account:  $ACCOUNT / $ENV_NAME"
say "  project:  $PROJECT"
say "  SA:       $SA_EMAIL"
say "  WIF:      $WIF_PROVIDER_RESOURCE"
say "  sops:     $AUTH_REL"
say "  OPEN:     $OPEN_URL"
