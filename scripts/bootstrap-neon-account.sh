#!/usr/bin/env bash
# scripts/bootstrap-neon-account.sh
#
# Independent Neon org bootstrap for cloud.deployment — NOT coupled to GCP.
#
# Creates nothing on GCP. Registers a Neon domain account key and stores the
# org API key as SOPS-encrypted metadata (same age recipient as deployment.infra
# / GCP bootstrap). CI decrypts this file with repository secret SOPS_AGE_KEY.
#
# Neon org itself is created in the Neon console (or Neon API with a personal
# key). This script only onboards the key into our registries + credential store.
#
# Linkage to GCP is per app only:
#   app.yaml → neon.account  (this script)
#            → gcp.account   (bootstrap-gcp-account.sh)
#
# Usage:
#   export GITHUB_TOKEN=ghp_xxx
#   export API_KEY=napi_xxx          # org API key from Neon console
#   ./bootstrap-neon-account.sh --account identity
#
#   ./bootstrap-neon-account.sh --account payments --api-key "$API_KEY" \
#     --org-hint "Stawi Payments"
#
# Flags:
#   --account <KEY>       neon-accounts.yaml key (required): identity|payments|…
#   --api-key <KEY>       Neon org API key (or env API_KEY / NEON_ORG_API_KEY)
#   --org-hint <NAME>     Optional human label for the Neon org
#   --org-id <ID>         Optional Neon org id (metadata only)
#   --sync-github-env     DEPRECATED no-op (CI uses SOPS, not neon--* GH envs)
#   --repo-path <PATH>    cloud.deployment checkout
#   --no-clone / --no-push / --no-pr / --force-repo-write / --metadata-only
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

ACCOUNT=""
# Accept NEON_API_KEY as alias for the org API key value (not a GitHub secret name)
API_KEY="${API_KEY:-${NEON_API_KEY:-${NEON_ORG_API_KEY:-}}}"
ORG_HINT=""
ORG_ID=""
SYNC_GH_ENV="false"
REPO_PATH=""
BASE_BRANCH="main"
BRANCH=""
NO_PUSH="false"
NO_PR="false"
NO_CLONE="false"
FORCE_REPO_WRITE="false"
METADATA_ONLY="false"   # update registry only; no secret in sops (key already stored elsewhere)

GITHUB_REPO="stawi-org/cloud.deployment"
SOPS_VERSION="v3.11.0"
CLONE_URL="https://github.com/${GITHUB_REPO}.git"
DEFAULT_CLONE_DIR="${HOME}/cloud.deployment"

say()  { printf '\e[1;34m[%s][neon]\e[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\e[1;33m[%s][neon]\e[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '\e[1;31m[%s][neon]\e[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}" 2>/dev/null || true
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account)          ACCOUNT="$2"; shift 2 ;;
    --api-key)          API_KEY="$2"; shift 2 ;;
    --org-hint)         ORG_HINT="$2"; shift 2 ;;
    --org-id)           ORG_ID="$2"; shift 2 ;;
    --sync-github-env)  SYNC_GH_ENV="true"; shift ;;
    --repo-path)        REPO_PATH="$2"; shift 2 ;;
    --base-branch)      BASE_BRANCH="$2"; shift 2 ;;
    --branch)           BRANCH="$2"; shift 2 ;;
    --no-push)          NO_PUSH="true"; shift ;;
    --no-pr)            NO_PR="true"; shift ;;
    --no-clone)         NO_CLONE="true"; shift ;;
    --force-repo-write) FORCE_REPO_WRITE="true"; shift ;;
    --metadata-only)    METADATA_ONLY="true"; shift ;;
    -h|--help)          usage ;;
    --project|--gcp-*)
      die "This is Neon-only bootstrap. Use scripts/bootstrap-gcp-account.sh for GCP."
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$ACCOUNT" ]] || die "--account is required (e.g. identity)"
if [[ "$ACCOUNT" == *"/"* || "$ACCOUNT" == *".."* ]]; then
  die "--account must be a single path segment"
fi
if [[ "$METADATA_ONLY" != "true" && -z "$API_KEY" ]]; then
  die "pass --api-key or set API_KEY / NEON_ORG_API_KEY (or use --metadata-only)"
fi

BRANCH="${BRANCH:-onboard-neon-${ACCOUNT}}"

# -------- helpers --------
ensure_sops() {
  if command -v sops >/dev/null 2>&1; then return 0; fi
  local dest="${HOME}/.local/bin" arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "unsupported arch for sops: $arch" ;;
  esac
  mkdir -p "$dest"
  say "installing sops ${SOPS_VERSION}"
  curl -fsSL -o "${dest}/sops" \
    "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${arch}"
  chmod +x "${dest}/sops"
  export PATH="${dest}:${PATH}"
  command -v sops >/dev/null 2>&1 || die "failed to install sops"
}

ensure_yq() {
  if command -v yq >/dev/null 2>&1; then return 0; fi
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "unsupported arch for yq" ;;
  esac
  mkdir -p "${HOME}/.local/bin"
  curl -fsSL -o "${HOME}/.local/bin/yq" \
    "https://github.com/mikefarah/yq/releases/download/v4.44.6/yq_linux_${arch}"
  chmod +x "${HOME}/.local/bin/yq"
  export PATH="${HOME}/.local/bin:${PATH}"
  command -v yq >/dev/null 2>&1 || die "yq required"
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
    "https://api.github.com/user" 2>/dev/null | jq -r '.login // empty'
}

github_ensure_fork() {
  local token="$1" login fork_full
  login=$(github_login "$token") || true
  [[ -n "$login" ]] || return 1
  fork_full="${login}/${GITHUB_REPO#*/}"
  if curl -fsS -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${token}" \
      "https://api.github.com/repos/${fork_full}" 2>/dev/null | grep -qx '200'; then
    printf '%s' "$fork_full"; return 0
  fi
  say "creating fork ${fork_full}"
  local code
  code=$(curl -sS -o /tmp/neon-fork.json -w '%{http_code}' -X POST \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/forks" || true)
  [[ "$code" == "202" || "$code" == "200" ]] || return 1
  local i
  for ((i = 1; i <= 30; i++)); do
    curl -fsS -o /dev/null -H "Authorization: Bearer ${token}" \
      "https://api.github.com/repos/${fork_full}" 2>/dev/null && { printf '%s' "$fork_full"; return 0; }
    sleep 2
  done
  return 1
}

git_push_noninteractive() {
  local url="$1" refspec="$2"
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true \
    git -c credential.helper= -c core.askPass=/bin/true \
      push --porcelain "$url" "$refspec" 2>/tmp/neon-git-push.err
}

github_api() {
  local method="$1" path="$2"
  shift 2
  local token
  token="$(github_token)" || die "GITHUB_TOKEN required"
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
    [[ -n "$pr_url" ]] && { say "PR already open: $pr_url"; printf '%s\n' "$pr_url"; return 0; }
  fi
  warn "create PR failed (HTTP ${code})"
  return 1
}

# GitHub Environment secret API_KEY (CI fallback path).
# Prefer `gh secret set --env` when available — fewer permission footguns than raw API.
sync_github_environment_secret() {
  local env_name="$1" secret_value="$2"
  local token
  token="$(github_token)" || die "GITHUB_TOKEN required for --sync-github-env"

  # --- Preferred path: GitHub CLI (no Python/pynacl) ---
  if command -v gh >/dev/null 2>&1; then
    say "setting GitHub Environment secret via gh (env=${env_name})"
    # Ensure environment exists first (gh secret set may require it).
    # Create via API with clear errors; ignore if already exists.
    local pre_code pre_body
    pre_body=$(mktemp)
    pre_code=$(curl -sS -o "$pre_body" -w '%{http_code}' -X PUT \
      -H "Authorization: Bearer ${token}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      "https://api.github.com/repos/${GITHUB_REPO}/environments/${env_name}" \
      -d '{}' || echo "000")
    if [[ "$pre_code" == "403" ]]; then
      rm -f "$pre_body"
      die "cannot create GitHub Environment '${env_name}' (HTTP 403).

Your PAT cannot manage environments. Either:
  • Add fine-grained permission Administration: Read and write (plus Environments), or
  • Create '${env_name}' in the UI and set secret API_KEY manually, then re-run
    without --sync-github-env.

UI: https://github.com/${GITHUB_REPO}/settings/environments"
    fi
    rm -f "$pre_body"

    if GH_TOKEN="$token" GH_PROMPT_DISABLED=1 \
        printf '%s' "$secret_value" \
        | GH_TOKEN="$token" GH_PROMPT_DISABLED=1 gh secret set API_KEY \
            --repo "$GITHUB_REPO" \
            --env "$env_name" 2>/tmp/neon-gh-secret.err; then
      say "  set ${env_name} / API_KEY via gh"
      return 0
    fi
    # older gh uses --body -
    if GH_TOKEN="$token" GH_PROMPT_DISABLED=1 \
        printf '%s' "$secret_value" \
        | GH_TOKEN="$token" GH_PROMPT_DISABLED=1 gh secret set API_KEY \
            --repo "$GITHUB_REPO" \
            --env "$env_name" \
            --body - 2>>/tmp/neon-gh-secret.err; then
      say "  set ${env_name} / API_KEY via gh"
      return 0
    fi
    warn "gh secret set failed:"
    head -c 500 /tmp/neon-gh-secret.err >&2 || true
    printf '\n' >&2
    warn "falling back to REST API + pynacl venv…"
  else
    warn "gh not installed — using REST + pynacl (install gh to avoid Python deps: https://cli.github.com)"
  fi

  # --- REST: create environment, then encrypt + put secret ---
  say "ensuring GitHub Environment ${env_name} (REST)"
  local create_body create_code
  create_body=$(mktemp)
  create_code=$(curl -sS -o "$create_body" -w '%{http_code}' -X PUT \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${GITHUB_REPO}/environments/${env_name}" \
    -d '{}')
  case "$create_code" in
    200|201)
      say "  environment ok (HTTP ${create_code})"
      ;;
    404)
      rm -f "$create_body"
      die "GitHub returned 404 creating environment '${env_name}' on ${GITHUB_REPO}.

Common causes:
  1) Token cannot see the repo (wrong GITHUB_TOKEN / SSO not authorized for stawi-org)
  2) Token lacks permission to manage Environments
     - classic PAT: repo scope (and admin on the repo)
     - fine-grained: Repository permissions → Environments: Read and Write
       plus Metadata: Read; often also Administration: Read
  3) You are not an admin of ${GITHUB_REPO}

Workaround (no API): UI → Settings → Environments → New environment '${env_name}'
  → Environment secrets → API_KEY = your Neon org API key
Then re-run without --sync-github-env (SOPS/PR path only), or with --sync-github-env after env exists.

Response: $(head -c 300 "$create_body" 2>/dev/null || true)"
      ;;
    403)
      die "GitHub 403 creating environment '${env_name}' — token lacks Environments write / admin on ${GITHUB_REPO}.
$(head -c 400 "$create_body" 2>/dev/null || true)"
      ;;
    *)
      die "create environment HTTP ${create_code}: $(head -c 400 "$create_body" 2>/dev/null || true)"
      ;;
  esac
  rm -f "$create_body"

  local pk_body pk_code pk_json key_id pub
  pk_body=$(mktemp)
  pk_code=$(curl -sS -o "$pk_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${GITHUB_REPO}/environments/${env_name}/secrets/public-key")
  if [[ "$pk_code" != "200" ]]; then
    die "get env public-key HTTP ${pk_code} for ${env_name} (env may not exist or token cannot read secrets).
$(head -c 400 "$pk_body" 2>/dev/null || true)"
  fi
  pk_json=$(cat "$pk_body")
  rm -f "$pk_body"
  key_id=$(jq -r '.key_id // empty' <<<"$pk_json")
  pub=$(jq -r '.key // empty' <<<"$pk_json")
  [[ -n "$key_id" && -n "$pub" ]] || die "public-key response missing key_id/key"

  # Encrypt for GitHub's libsodium sealbox. Never pip-install into system
  # Python (PEP 668 / externally-managed-environment on Debian/Ubuntu).
  local encrypted venv_dir py
  venv_dir=$(mktemp -d)
  py=""
  if python3 -c 'from nacl import public' 2>/dev/null; then
    py="python3"
  else
    say "  installing pynacl in temporary venv (system pip is blocked on this OS)"
    python3 -m venv "$venv_dir" \
      || die "python3 -m venv failed — install python3-venv (e.g. sudo apt install python3-venv python3-full)"
    # shellcheck disable=SC1091
    # Use venv pip only
    "$venv_dir/bin/pip" install -q --disable-pip-version-check pynacl \
      || die "pip install pynacl in venv failed"
    py="$venv_dir/bin/python"
  fi
  encrypted=$("$py" - "$pub" "$secret_value" <<'PY'
import base64, sys
from nacl import encoding, public
pub_b64, secret = sys.argv[1], sys.argv[2]
pubkey = public.PublicKey(pub_b64.encode("utf-8"), encoding.Base64Encoder())
sealed = public.SealedBox(pubkey).encrypt(secret.encode("utf-8"))
print(base64.b64encode(sealed).decode("utf-8"))
PY
  ) || die "failed to encrypt secret for GitHub (pynacl)"
  rm -rf "$venv_dir"

  local put_body put_code
  put_body=$(mktemp)
  put_code=$(curl -sS -o "$put_body" -w '%{http_code}' -X PUT \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${GITHUB_REPO}/environments/${env_name}/secrets/API_KEY" \
    -d "$(jq -n --arg k "$key_id" --arg v "$encrypted" '{encrypted_value:$v, key_id:$k}')")
  if [[ "$put_code" != "201" && "$put_code" != "204" ]]; then
    die "put environment secret HTTP ${put_code}: $(head -c 400 "$put_body" 2>/dev/null || true)"
  fi
  rm -f "$put_body"
  say "  set ${env_name} / API_KEY via REST"
}

ensure_git_clone() {
  local dest="$1"
  if [[ -d "$dest/.git" && -f "$dest/config/neon-accounts.yaml" ]]; then
    say "reusing clone at $dest"
    git -C "$dest" fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true
    git -C "$dest" checkout "$BASE_BRANCH" --quiet 2>/dev/null \
      || git -C "$dest" checkout -B "$BASE_BRANCH" "origin/${BASE_BRANCH}" --quiet 2>/dev/null || true
    git -C "$dest" pull --ff-only origin "$BASE_BRANCH" --quiet 2>/dev/null || true
    return 0
  fi
  [[ -e "$dest" && ! -d "$dest/.git" ]] && die "$dest exists but is not a git clone"
  say "cloning ${CLONE_URL} → ${dest}"
  mkdir -p "$(dirname "$dest")"
  git clone --branch "$BASE_BRANCH" --single-branch "$CLONE_URL" "$dest" \
    || git clone "$CLONE_URL" "$dest" \
    || die "git clone failed"
}

resolve_repo_path() {
  if [[ -n "$REPO_PATH" ]]; then
    if [[ ! -f "$REPO_PATH/config/neon-accounts.yaml" ]]; then
      [[ "$NO_CLONE" == "true" ]] && die "not a cloud.deployment checkout"
      ensure_git_clone "$REPO_PATH"
    fi
  else
    local detected
    detected=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$detected" && -f "$detected/config/neon-accounts.yaml" ]]; then
      REPO_PATH="$detected"
    elif [[ "$NO_CLONE" == "true" ]]; then
      die "not in cloud.deployment checkout and --no-clone set"
    else
      REPO_PATH="$DEFAULT_CLONE_DIR"
      ensure_git_clone "$REPO_PATH"
    fi
  fi
  REPO_PATH="$(cd "$REPO_PATH" && pwd)"
  [[ -f "$REPO_PATH/config/neon-accounts.yaml" ]] || die "missing config/neon-accounts.yaml"
  [[ -f "$REPO_PATH/.sops.yaml" ]] || die "missing .sops.yaml"
  say "repo path: $REPO_PATH"
}

# -------- prereqs --------
ensure_sops
ensure_yq
for cmd in jq curl python3 git sops yq; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing: $cmd"
done

resolve_repo_path

if ! yq -e ".accounts[\"${ACCOUNT}\"]" "$REPO_PATH/config/neon-accounts.yaml" >/dev/null 2>&1; then
  die "account '${ACCOUNT}' not in config/neon-accounts.yaml — add the domain key to the registry first"
fi

# Optional live check against Neon API
if [[ -n "$API_KEY" && "$METADATA_ONLY" != "true" ]]; then
  say "validating Neon API key (GET /users/me)"
  code=$(curl -sS -o /tmp/neon-me.json -w '%{http_code}' \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Accept: application/json" \
    "https://console.neon.tech/api/v2/users/me" || true)
  if [[ "$code" == "200" ]]; then
    email=$(jq -r '.email // .id // "ok"' /tmp/neon-me.json 2>/dev/null || echo ok)
    say "  Neon API ok (${email})"
  else
    warn "  Neon API returned HTTP ${code} — key may still work for org-scoped endpoints; continuing"
  fi
fi

# GitHub Environment secrets are no longer used by CI (SOPS + SOPS_AGE_KEY).
if [[ "$SYNC_GH_ENV" == "true" ]]; then
  warn "--sync-github-env is deprecated and ignored."
  warn "CI loads Neon API keys from credentials/neon/<account>/auth.yaml via SOPS_AGE_KEY."
  warn "Ensure repository secret SOPS_AGE_KEY is set (private age key matching .sops.yaml)."
fi

AUTH_REL="credentials/neon/${ACCOUNT}/auth.yaml"

already="false"
if git -C "$REPO_PATH" rev-parse --verify "origin/${BASE_BRANCH}" >/dev/null 2>&1 \
    || git -C "$REPO_PATH" fetch origin "$BASE_BRANCH" --quiet 2>/dev/null; then
  if git -C "$REPO_PATH" cat-file -e "origin/${BASE_BRANCH}:${AUTH_REL}" 2>/dev/null; then
    already="true"
  fi
fi
if [[ "$already" == "true" && "$FORCE_REPO_WRITE" != "true" ]]; then
  say "already have ${AUTH_REL} on origin/${BASE_BRANCH}"
  say "use --force-repo-write to refresh"
  exit 0
fi

# -------- worktree --------
WORKTREE="${REPO_PATH}/.worktrees/${BRANCH}"
rm -rf "$WORKTREE" 2>/dev/null || true
git -C "$REPO_PATH" fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true
git -C "$REPO_PATH" worktree prune 2>/dev/null || true
if git -C "$REPO_PATH" show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  git -C "$REPO_PATH" branch -D "$BRANCH" >/dev/null 2>&1 || true
fi
git -C "$REPO_PATH" worktree add -b "$BRANCH" "$WORKTREE" "origin/${BASE_BRANCH}" 2>/dev/null \
  || git -C "$REPO_PATH" worktree add -b "$BRANCH" "$WORKTREE" "$BASE_BRANCH" \
  || die "could not create worktree"
say "worktree: $WORKTREE"

# Optional metadata updates on registry (non-secret)
if [[ -n "$ORG_HINT" ]]; then
  yq -i ".accounts[\"${ACCOUNT}\"].neon_org_hint = \"${ORG_HINT}\"" \
    "$WORKTREE/config/neon-accounts.yaml"
fi
if [[ -n "$ORG_ID" ]]; then
  yq -i ".accounts[\"${ACCOUNT}\"].neon_org_id = \"${ORG_ID}\"" \
    "$WORKTREE/config/neon-accounts.yaml"
fi
# Document sops path for operators (non-secret); drop legacy github_environment if present
yq -i ".accounts[\"${ACCOUNT}\"].sops_auth_path = \"${AUTH_REL}\"" \
  "$WORKTREE/config/neon-accounts.yaml"
yq -i "del(.accounts[\"${ACCOUNT}\"].github_environment)" \
  "$WORKTREE/config/neon-accounts.yaml" 2>/dev/null || true

# SOPS auth with API key (unless metadata-only)
mkdir -p "$WORKTREE/credentials/neon/${ACCOUNT}"
if [[ "$METADATA_ONLY" != "true" ]]; then
  AUTH_PLAIN=$(mktemp)
  umask 077
  cat >"$AUTH_PLAIN" <<EOF
auth:
  account_key: ${ACCOUNT}
  neon_org_hint: ${ORG_HINT:-}
  neon_org_id: ${ORG_ID:-}
  api_key: ${API_KEY}
  bootstrapped_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  note: "Neon org API key for OpenTofu provider only — never inject into Cloud Run; CI decrypts via SOPS_AGE_KEY"
EOF
  # filename-override: match .sops.yaml creation_rules (not the /tmp plaintext path)
  (
    cd "$WORKTREE"
    sops encrypt --filename-override "$AUTH_REL" "$AUTH_PLAIN" >"$AUTH_REL"
  )
  rm -f "$AUTH_PLAIN"
  grep -q '^sops:' "$WORKTREE/$AUTH_REL" || die "SOPS encrypt failed"
  say "wrote encrypted $AUTH_REL"
else
  say "--metadata-only: skip writing api_key to SOPS"
fi

mkdir -p "$WORKTREE/credentials"
cat >"$WORKTREE/credentials/README.md" <<'EOF'
# Encrypted credentials

SOPS age recipient is in repo `.sops.yaml`. CI uses repository secret `SOPS_AGE_KEY`.

## GCP
- `credentials/gcp/<account>/<env>/auth.yaml` — from `scripts/bootstrap-gcp-account.sh`
- Non-secret project/WIF also in `config/gcp-accounts.yaml`

## Neon (independent of GCP)
- `credentials/neon/<account>/auth.yaml` — from `scripts/bootstrap-neon-account.sh`
- Contains org API key (SOPS). CI decrypts when app has `neon.account`.
- Non-secret registry: `config/neon-accounts.yaml`
- Apps link Neon↔GCP only via `app.yaml` (`neon.account` + `gcp.account`)

Decrypt (private age key required):

```bash
export SOPS_AGE_KEY='AGE-SECRET-KEY-...'
sops -d credentials/neon/identity/auth.yaml
sops -d credentials/gcp/identity/stawi-prod/auth.yaml
```
EOF

cd "$WORKTREE"
if ! git config user.email >/dev/null 2>&1; then
  git config user.email "${GIT_AUTHOR_EMAIL:-bootstrap-neon@stawi.org}"
fi
if ! git config user.name >/dev/null 2>&1; then
  git config user.name "${GIT_AUTHOR_NAME:-bootstrap-neon-account}"
fi

git add config/neon-accounts.yaml credentials/README.md .sops.yaml 2>/dev/null || true
[[ -f "$AUTH_REL" ]] && git add "$AUTH_REL"

if git diff --cached --quiet; then
  say "no changes to commit"
else
  git commit -m "onboard neon ${ACCOUNT}: SOPS auth + registry metadata"
  say "committed on $BRANCH"
fi

OPEN_URL="https://github.com/${GITHUB_REPO}/compare/${BASE_BRANCH}...${BRANCH}?expand=1"
PR_HEAD="$BRANCH"
PUSH_OK="false"
TOKEN=$(github_token 2>/dev/null || true)

pr_body() {
  cat <<EOF
## Onboard Neon account \`${ACCOUNT}\`

Independent of GCP. Stores org API key as SOPS-encrypted credential and updates \`config/neon-accounts.yaml\` metadata.

| Field | Value |
|-------|--------|
| neon.account | \`${ACCOUNT}\` |
| sops path | \`${AUTH_REL}\` |
| org hint | \`${ORG_HINT:-}\` |

### After merge

- Apps with \`neon.account: ${ACCOUNT}\` use this Neon org for database projects.
- Pair with any \`gcp.account\` independently in \`app.yaml\`.
- CI decrypts \`${AUTH_REL}\` with repository secret \`SOPS_AGE_KEY\` (no \`neon--*\` GitHub Environments).
EOF
}

if [[ "$NO_PUSH" == "true" ]]; then
  say "skipping push (--no-push)"
  say "OPEN: $OPEN_URL"
  exit 0
fi

REFSPEC="HEAD:refs/heads/${BRANCH}"
if [[ -n "$TOKEN" ]]; then
  token_url="https://x-access-token:${TOKEN}@github.com/${GITHUB_REPO}.git"
  if git_push_noninteractive "$token_url" "$REFSPEC"; then
    PUSH_OK="true"
  else
    if fork_full=$(github_ensure_fork "$TOKEN"); then
      if git_push_noninteractive "https://x-access-token:${TOKEN}@github.com/${fork_full}.git" "$REFSPEC"; then
        PUSH_OK="true"
        PR_HEAD="${fork_full%%/*}:${BRANCH}"
        OPEN_URL="https://github.com/${GITHUB_REPO}/compare/${BASE_BRANCH}...${PR_HEAD}?expand=1"
      fi
    fi
  fi
else
  git_push_noninteractive "https://github.com/${GITHUB_REPO}.git" "$REFSPEC" && PUSH_OK="true" || true
fi

if [[ "$PUSH_OK" != "true" ]]; then
  cat <<EOF

Neon credential files prepared. Push needs a token:

  export GITHUB_TOKEN=ghp_xxx
  ./bootstrap-neon-account.sh --account ${ACCOUNT} --api-key "\$API_KEY" --force-repo-write

Branch: ${BRANCH}
EOF
  exit 0
fi

if [[ "$NO_PR" != "true" && -n "$TOKEN" ]]; then
  if pr_url=$(github_create_pr "onboard neon ${ACCOUNT}" "$PR_HEAD" "$BASE_BRANCH" "$(pr_body)"); then
    [[ -n "$pr_url" ]] && OPEN_URL="$pr_url"
  fi
fi

say ""
say "Done (Neon only — no GCP changes)."
say "  account:  $ACCOUNT"
say "  sops:     $AUTH_REL"
say "  CI:       SOPS_AGE_KEY repo secret decrypts this file"
say "  OPEN:     $OPEN_URL"
