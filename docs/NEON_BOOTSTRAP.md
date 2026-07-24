# Bootstrap a Neon account (independent of GCP)

Neon organizations are created and managed **separately from GCP**.  
This script only onboards a domain account key + API key into **cloud.deployment**.

GCP bootstrap: [GCP_BOOTSTRAP.md](GCP_BOOTSTRAP.md) / `scripts/bootstrap-gcp-account.sh`  
Neon bootstrap: this doc / `scripts/bootstrap-neon-account.sh`

## Model

```
Neon console  →  create org + API key
       ↓
bootstrap-neon-account.sh
       ↓
  config/neon-accounts.yaml     (non-secret metadata)
  credentials/neon/<account>/auth.yaml   (SOPS: api_key)
  optional: GitHub Environment NEON_API_KEY
       ↓
app.yaml  neon.account: identity   ← only linkage to apps
app.yaml  gcp.account:  identity   ← separate GCP bootstrap
```

There is **no** requirement that a Neon org and a GCP project share a name or be created together.

## Script

[`scripts/bootstrap-neon-account.sh`](../scripts/bootstrap-neon-account.sh)

### What it does

| Step | Action |
|------|--------|
| 1 | Validate API key (best-effort `GET /users/me`) |
| 2 | Optional: create GH Environment + secret `NEON_API_KEY` (`--sync-github-env`) |
| 3 | PR: update `config/neon-accounts.yaml` metadata (`sops_auth_path`, hints) |
| 4 | PR: SOPS-encrypt `credentials/neon/<account>/auth.yaml` (age, same as GCP creds) |

Does **not**: create Neon orgs (use Neon console/API), touch GCP, or write Cloud Run secrets.

### Usage

```bash
curl -fsSL https://raw.githubusercontent.com/stawi-org/cloud.deployment/main/scripts/bootstrap-neon-account.sh \
  -o bootstrap-neon-account.sh
chmod +x bootstrap-neon-account.sh

export GITHUB_TOKEN=ghp_xxxxxxxx
export NEON_API_KEY=napi_xxxxxxxx   # from Neon console → Account settings → API keys

./bootstrap-neon-account.sh \
  --account identity \
  --org-hint "Stawi Identity" \
  --sync-github-env
```

| Flag | Purpose |
|------|---------|
| `--account` | Key in `config/neon-accounts.yaml` (`identity`, `payments`, …) |
| `--api-key` | Org API key (or `NEON_API_KEY` / `NEON_ORG_API_KEY` env) |
| `--org-hint` | Human label stored in registry |
| `--org-id` | Optional Neon org id metadata |
| `--sync-github-env` | Upsert GH Environment secret `NEON_API_KEY` for CI fallback |
| `--metadata-only` | Registry only; do not put key in SOPS (if key only lives in GH Env) |
| `--force-repo-write` | Refresh PR even if SOPS file already on main |

Account key must already exist in `config/neon-accounts.yaml` (planned domain). Add new domains by PR to the registry first, then bootstrap.

### Token requirements for `--sync-github-env`

| Auth | Needs |
|------|--------|
| Classic PAT | `repo` scope; you must be **admin** on `stawi-org/cloud.deployment` |
| Fine-grained PAT | Resource owner `stawi-org`, repo `cloud.deployment`; **Environments: Read and write**; Metadata: Read |
| Org SSO | Authorize the token for `stawi-org` (SSO authorize button on the token) |

If you see **`curl: (22) … 404`** on environment create/public-key:

1. Confirm `GITHUB_TOKEN` is for a user/admin that can open  
   https://github.com/stawi-org/cloud.deployment/settings/environments  
2. Or create the environment manually, add secret `NEON_API_KEY`, then re-run **without** `--sync-github-env` (SOPS/PR only), or with it after the env exists.  
3. Prefer installing `gh` and re-running — the script uses `gh secret set --env` first when available.  
4. If you see **`externally-managed-environment` / `No module named 'nacl'`**: the REST fallback tried to `pip install pynacl` into system Python (blocked on modern Debian/Ubuntu). Pull the latest script (uses a temp venv), or install `python3-venv` / use `gh`, or set the secret in the UI and omit `--sync-github-env`.

## After merge

```bash
# App uses Neon org independently of which GCP project it deploys to:
# apps/foo/app.yaml
#   gcp:
#     account: identity      # from GCP bootstrap
#   neon:
#     account: identity      # from this bootstrap
```

CI resolution (`resolve-app-context.sh` / `app-tofu.yml`):

1. Prefer Neon key from GitHub Environment or Secret Manager (when WIF + SM configured separately)  
2. SOPS file is the **operator break-glass / audit copy** (private age key to decrypt)

## Related

- [BACKEND.md](BACKEND.md) — multi-account model  
- [GCP_BOOTSTRAP.md](GCP_BOOTSTRAP.md) — GCP-only onboard  
- Neon multi-account design under `docs/superpowers/specs/`  
