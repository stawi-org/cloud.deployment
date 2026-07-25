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
# Extra APIs beyond core Cloud Run stack
EXTRA_APIS=(
  serviceusage.googleapis.com
)

usage() {
  if [[ -n "${BASH_SOURCE[0]:-}" && -r "${BASH_SOURCE[0]}" ]]; then
    awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' \
      "${BASH_SOURCE[0]}"
  fi
  cat <<'EOF'

Flags:
  --project <ID>         GCP project id (required)
  --account <KEY>        gcp-accounts.yaml account key (required)
                         e.g. identity | platform | operations | payments
                         New keys are auto-created in the registry PR if missing.
  --env <NAME>           stawi-dev | stawi-prod (default: stawi-dev)
                         Env slices are auto-created if missing.
  --region <REGION>      Default europe-west1
  --repo-path <PATH>     cloud.deployment checkout (default: auto-clone ~/cloud.deployment)
                         Existing checkouts are always fetched + reset to origin/<base-branch>
  --no-clone             Fail if no checkout found (still syncs to latest base branch)
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
[[ -n "$ACCOUNT" ]] || die "--account is required (e.g. identity | operations)"
case "$ENV_NAME" in
  stawi-dev|stawi-prod) ;;
  *) die "--env must be stawi-dev or stawi-prod (got: $ENV_NAME)" ;;
esac
# Stable registry keys only: lower-case letter, then alnum/hyphen (no path tricks).
if [[ ! "$ACCOUNT" =~ ^[a-z][a-z0-9-]*$ ]]; then
  die "--account must match ^[a-z][a-z0-9-]*$ (got: ${ACCOUNT})"
fi
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

ensure_yq() {
  if command -v yq >/dev/null 2>&1; then
    return 0
  fi
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "unsupported arch for yq: $arch" ;;
  esac
  mkdir -p "${HOME}/.local/bin"
  say "installing yq → ${HOME}/.local/bin/yq"
  curl -fsSL -o "${HOME}/.local/bin/yq" \
    "https://github.com/mikefarah/yq/releases/download/v4.44.6/yq_linux_${arch}"
  chmod +x "${HOME}/.local/bin/yq"
  export PATH="${HOME}/.local/bin:${PATH}"
  command -v yq >/dev/null 2>&1 || die "yq required"
}

# Confirm sops can encrypt using .sops.yaml rules (catches misconfig early).
preflight_sops() {
  local repo="$1"
  local probe plain out
  plain=$(mktemp)
  out=$(mktemp)
  printf 'auth:\n  probe: true\n' >"$plain"
  if ! (
    cd "$repo"
    sops encrypt --filename-override "credentials/gcp/_probe/stawi-dev/auth.yaml" "$plain" >"$out"
  ); then
    rm -f "$plain" "$out"
    die "sops encrypt preflight failed — check .sops.yaml age recipient and sops version (need 'sops encrypt')"
  fi
  if ! grep -q '^sops:' "$out"; then
    rm -f "$plain" "$out"
    die "sops encrypt preflight produced non-sops output"
  fi
  rm -f "$plain" "$out"
  say "sops encrypt preflight ok"
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

# Bring an existing checkout onto origin/${BASE_BRANCH} (latest main by default).
# Stashes local dirt so Cloud Shell re-runs always pick up registry/script fixes.
sync_checkout_to_base() {
  local dest="$1"
  [[ -d "$dest/.git" ]] || die "not a git checkout: $dest"

  say "syncing ${dest} → origin/${BASE_BRANCH}"

  # Prefer origin as the GitHub remote; tolerate alternate remote names.
  if ! git -C "$dest" remote get-url origin >/dev/null 2>&1; then
    if git -C "$dest" remote | grep -qx 'upstream'; then
      git -C "$dest" remote rename upstream origin 2>/dev/null || true
    fi
  fi
  if git -C "$dest" remote get-url origin >/dev/null 2>&1; then
    local cur
    cur=$(git -C "$dest" remote get-url origin 2>/dev/null || true)
    if [[ -n "$cur" && "$cur" != *"${GITHUB_REPO}"* && "$cur" != *"${GITHUB_REPO%.git}"* ]]; then
      warn "origin remote is '${cur}' (expected ${GITHUB_REPO}); fetching anyway"
    fi
  else
    say "adding origin → ${CLONE_URL}"
    git -C "$dest" remote add origin "$CLONE_URL"
  fi

  if ! git -C "$dest" fetch --prune origin "$BASE_BRANCH"; then
    # Fallback: full fetch if branch refspec fails
    git -C "$dest" fetch --prune origin || die "git fetch origin failed — check network / GITHUB_TOKEN"
  fi
  git -C "$dest" rev-parse --verify --quiet "origin/${BASE_BRANCH}" >/dev/null \
    || die "origin/${BASE_BRANCH} not found after fetch"

  # Drop bootstrap worktrees that would block checkout (recreated later).
  if [[ -d "$dest/.worktrees" ]]; then
    git -C "$dest" worktree prune 2>/dev/null || true
  fi

  if [[ -n "$(git -C "$dest" status --porcelain 2>/dev/null || true)" ]]; then
    local stash_msg="bootstrap-gcp-account auto-stash $(date -u +%Y%m%dT%H%M%SZ)"
    warn "dirty working tree in ${dest} — stashing before reset (${stash_msg})"
    git -C "$dest" stash push -u -m "$stash_msg" || warn "stash failed; attempting hard reset anyway"
  fi

  # Detach any local branch tip onto remote tip (handles diverged local main).
  git -C "$dest" checkout -B "$BASE_BRANCH" "origin/${BASE_BRANCH}" \
    || die "could not checkout ${BASE_BRANCH} from origin/${BASE_BRANCH}"
  git -C "$dest" reset --hard "origin/${BASE_BRANCH}" \
    || die "git reset --hard origin/${BASE_BRANCH} failed"
  # Drop untracked noise that is not stashed (e.g. leftover editor files)
  git -C "$dest" clean -fd --exclude='.worktrees' 2>/dev/null || true

  local sha subject
  sha=$(git -C "$dest" rev-parse --short HEAD)
  subject=$(git -C "$dest" log -1 --pretty=format:'%s' 2>/dev/null || true)
  say "checkout at ${sha} on ${BASE_BRANCH}${subject:+ — ${subject}}"
}

ensure_git_clone() {
  local dest="$1"
  if [[ -d "$dest/.git" && -f "$dest/config/gcp-accounts.yaml" ]]; then
    say "existing clone at $dest — updating to latest ${BASE_BRANCH}"
    sync_checkout_to_base "$dest"
    return 0
  fi
  if [[ -e "$dest" && ! -d "$dest/.git" ]]; then
    die "$dest exists but is not a git clone"
  fi
  if [[ -d "$dest/.git" ]]; then
    # Partial/broken tree: has .git but missing registry — still try sync then validate
    say "git repo at $dest missing registry file — fetching ${BASE_BRANCH}"
    sync_checkout_to_base "$dest"
    [[ -f "$dest/config/gcp-accounts.yaml" ]] || die "after sync, still missing config/gcp-accounts.yaml in $dest"
    return 0
  fi
  say "cloning ${CLONE_URL} → ${dest} (branch ${BASE_BRANCH})"
  mkdir -p "$(dirname "$dest")"
  git clone --branch "$BASE_BRANCH" --single-branch "$CLONE_URL" "$dest" \
    || git clone "$CLONE_URL" "$dest" \
    || die "git clone failed"
  # Ensure we are exactly on latest tip (clone can race with a push)
  sync_checkout_to_base "$dest"
}

resolve_repo_path() {
  if [[ -n "$REPO_PATH" ]]; then
    if [[ ! -f "$REPO_PATH/config/gcp-accounts.yaml" || ! -d "$REPO_PATH/.git" ]]; then
      [[ "$NO_CLONE" == "true" ]] && die "--repo-path not a cloud.deployment checkout"
      ensure_git_clone "$REPO_PATH"
    else
      # Explicit path that already looks valid — still pull latest main
      sync_checkout_to_base "$REPO_PATH"
    fi
  else
    local detected
    detected=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$detected" && -f "$detected/config/gcp-accounts.yaml" ]]; then
      REPO_PATH="$detected"
      say "using checkout: $REPO_PATH"
      sync_checkout_to_base "$REPO_PATH"
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
ensure_yq
for cmd in gcloud jq curl git sops yq; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing: $cmd"
done

resolve_repo_path
verify_gcloud_access
preflight_sops "$REPO_PATH"

# Registry is optional going in — missing account/env are created in the PR.
# IAM-only mode only needs a valid GCP project; registry writes are skipped.
REG_FILE_LOCAL="$REPO_PATH/config/gcp-accounts.yaml"
if ! yq -e ".accounts[\"${ACCOUNT}\"]" "$REG_FILE_LOCAL" >/dev/null 2>&1; then
  say "account '${ACCOUNT}' not yet in gcp-accounts.yaml — will create it in the bootstrap PR"
elif ! yq -e ".accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"]" "$REG_FILE_LOCAL" >/dev/null 2>&1; then
  say "env '${ENV_NAME}' missing under accounts.${ACCOUNT} — will create it in the bootstrap PR"
else
  say "registry already has accounts.${ACCOUNT}.envs.${ENV_NAME} (will refresh from live WIF/SA)"
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
  cloudscheduler.googleapis.com \
  compute.googleapis.com \
  certificatemanager.googleapis.com \
  serviceusage.googleapis.com \
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
  roles/cloudscheduler.admin \
  roles/compute.admin \
  roles/certificatemanager.owner \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountUser \
  roles/storage.objectViewer \
  roles/serviceusage.serviceUsageConsumer \
  roles/logging.viewer \
  roles/artifactregistry.admin
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

# --- Update gcp-accounts.yaml (public registry; yq only) ---
# Auto-create account + env if missing so expansion is a single bootstrap call.
REG_FILE="$WORKTREE/config/gcp-accounts.yaml"
LABEL_ENV="dev"
[[ "$ENV_NAME" == "stawi-prod" ]] && LABEL_ENV="prod"
CREATED_ACCOUNT="false"
CREATED_ENV="false"
if ! yq -e ".accounts[\"${ACCOUNT}\"]" "$REG_FILE" >/dev/null 2>&1; then
  CREATED_ACCOUNT="true"
fi
if ! yq -e ".accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"]" "$REG_FILE" >/dev/null 2>&1; then
  CREATED_ENV="true"
fi

yq -i "
  .accounts[\"${ACCOUNT}\"] = (.accounts[\"${ACCOUNT}\"] // {}) |
  .accounts[\"${ACCOUNT}\"].description = (.accounts[\"${ACCOUNT}\"].description // \"GCP account ${ACCOUNT} (auto-registered by bootstrap-gcp-account.sh)\") |
  .accounts[\"${ACCOUNT}\"].owners = (.accounts[\"${ACCOUNT}\"].owners // [\"platform\"]) |
  .accounts[\"${ACCOUNT}\"].sensitivity = (.accounts[\"${ACCOUNT}\"].sensitivity // \"medium\") |
  .accounts[\"${ACCOUNT}\"].envs = (.accounts[\"${ACCOUNT}\"].envs // {}) |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"] = (.accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"] // {}) |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].project_id = \"${PROJECT}\" |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].region = \"${REGION}\" |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].workload_identity_provider = \"${WIF_PROVIDER_RESOURCE}\" |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].deploy_service_account = \"${SA_EMAIL}\" |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].sops_auth_path = \"${AUTH_REL}\" |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].labels = (.accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].labels // {}) |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].labels.\"managed-by\" = \"cloud-deployment\" |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].labels.domain = \"${ACCOUNT}\" |
  .accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].labels.environment = \"${LABEL_ENV}\" |
  del(.accounts[\"${ACCOUNT}\"].envs[\"${ENV_NAME}\"].protection_environment)
" "$REG_FILE"

if [[ "$CREATED_ACCOUNT" == "true" ]]; then
  say "created accounts.${ACCOUNT} in config/gcp-accounts.yaml"
fi
if [[ "$CREATED_ENV" == "true" ]]; then
  say "created accounts.${ACCOUNT}.envs.${ENV_NAME} in config/gcp-accounts.yaml"
fi
say "updated config/gcp-accounts.yaml → ${ACCOUNT}/${ENV_NAME} (project=${PROJECT})"

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
  note: "GCP deploy metadata — CI decrypts via SOPS_AGE_KEY; no Neon keys; runtime secrets in Secret Manager"
EOF

# filename-override: match .sops.yaml creation_rules (not the /tmp plaintext path)
(
  cd "$WORKTREE"
  sops encrypt --filename-override "$AUTH_REL" "$AUTH_PLAIN" >"$AUTH_FILE"
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

SOPS age recipient is in repo `.sops.yaml`. CI uses repository secret `SOPS_AGE_KEY`.

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
