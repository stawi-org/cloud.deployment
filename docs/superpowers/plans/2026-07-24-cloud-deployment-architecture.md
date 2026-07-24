# Cloud Deployment Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold `cloud.deployment` so each Cloud Run + Neon app is an independent OpenTofu root with R2 state, multi-account Neon support, path-filtered CI, and reusable modules—without any Kubernetes manifests in this repo.

**Architecture:** App-centric OpenTofu roots under `apps/<name>/cloudrun` compose path modules (`cloudrun-service`, `neon-database`, `edge-contract`) and platform defaults. GitHub Actions detects changed/impacted apps and matrixes plan/apply per `(app, env)` against R2 state keys `cloud-deployment/apps/<app>/<env>/terraform.tfstate`. All Kubernetes remains in `deployment.manifests`.

**Tech Stack:** OpenTofu ≥ 1.8 (target 1.10.0 to match `deployment.infra`), Google provider (Cloud Run + Secret Manager), Neon provider, S3-compatible R2 backend, bash + jq + yq for change detection, GitHub Actions.

**Spec:** [docs/superpowers/specs/2026-07-24-cloud-deployment-architecture-design.md](../specs/2026-07-24-cloud-deployment-architecture-design.md)

---

## File map (create)

| Path | Responsibility |
|------|----------------|
| `modules/edge-contract/{main,variables,outputs,versions}.tf` | Public edge defaults (hosts, CORS, OAuth bases, OTel) |
| `modules/neon-database/{main,variables,outputs,versions}.tf` | One Neon project per app; account-agnostic |
| `modules/cloudrun-service/{main,variables,outputs,versions}.tf` | Cloud Run service + SA + secret env |
| `platforms/stawi-dev/{main,outputs,versions}.tf` | Dev GCP/region/edge defaults |
| `platforms/stawi-prod/{main,outputs,versions}.tf` | Prod defaults |
| `apps/_template/app.yaml` | Metadata template |
| `apps/_template/cloudrun/*` | Thin root template + partial R2 backend |
| `config/neon-accounts.yaml` | Map account keys → env var names for API keys |
| `config/r2-backend.hcl` | Shared R2 backend partial config (no state key) |
| `.github/scripts/detect-changed-apps.sh` | Diff → JSON matrix of `{app,env}` |
| `.github/scripts/list-apps-using-module.sh` | Module path → consumer apps |
| `.github/scripts/tests/test-detect-changed-apps.sh` | Shell tests for detection |
| `.github/workflows/app-plan.yml` | PR plan matrix |
| `.github/workflows/app-apply.yml` | Main apply matrix |
| `.github/workflows/app-tofu.yml` | Reusable plan/apply for one app+env |
| `docs/ADDING_AN_APP.md` | Operator guide |
| `docs/MODULES.md` | Module contracts |
| `.tflint.hcl` | Lint config |
| `.pre-commit-config.yaml` | Optional local hooks |

**Never create:** HelmRelease, Flux Kustomization, HTTPRoute, CNPG, NATS YAML.

---

### Task 1: Shared R2 backend fragment and Neon account registry

**Files:**
- Create: `config/r2-backend.hcl`
- Create: `config/neon-accounts.yaml`
- Create: `docs/BACKEND.md`

- [ ] **Step 1: Write R2 backend partial (mirror deployment.infra)**

```hcl
# config/r2-backend.hcl
# Used via: tofu init -backend-config=../../../config/r2-backend.hcl \
#                     -backend-config="key=cloud-deployment/apps/<app>/<env>/terraform.tfstate"
bucket                      = "cluster-tofu-state"
region                      = "auto"
use_path_style              = true
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_region_validation      = true
skip_requesting_account_id  = true
skip_s3_checksum            = true
use_lockfile                = true
encrypt                     = true
# endpoints.s3 supplied at init:
#   -backend-config="endpoints={s3=\"https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com\"}"
```

- [ ] **Step 2: Write Neon account registry**

```yaml
# config/neon-accounts.yaml
# app.yaml neon.account must match a key here.
# CI exports the secret named by api_key_secret into NEON_API_KEY for that job.
accounts:
  stawi-org:
    api_key_secret: NEON_API_KEY_STAWI_ORG
    description: Primary Stawi Neon organization
  stawi-labs:
    api_key_secret: NEON_API_KEY_STAWI_LABS
    description: Labs / experimental Neon organization
```

- [ ] **Step 3: Document backend + required GitHub secrets**

Create `docs/BACKEND.md` with:

- State key pattern: `cloud-deployment/apps/<app>/<env>/terraform.tfstate`
- Required secrets: `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`
- Per Neon account secrets listed in `config/neon-accounts.yaml`
- GCP WIF secrets/vars for Cloud Run apply (placeholder names: `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT` — wire fully in Task 8)
- Note: same R2 bucket name as `deployment.infra` (`cluster-tofu-state`) is intentional; key prefix isolates this repo

- [ ] **Step 4: Commit**

```bash
git add config/r2-backend.hcl config/neon-accounts.yaml docs/BACKEND.md
git commit -m "chore: add R2 backend fragment and Neon account registry"
```

---

### Task 2: Change-detection scripts (TDD)

**Files:**
- Create: `.github/scripts/detect-changed-apps.sh`
- Create: `.github/scripts/list-apps-using-module.sh`
- Create: `.github/scripts/tests/test-detect-changed-apps.sh`
- Create: fixture tree under `.github/scripts/tests/fixtures/` (minimal fake monorepo)

- [ ] **Step 1: Write failing shell tests**

Create `.github/scripts/tests/test-detect-changed-apps.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/detect-changed-apps.sh"
FIX="$ROOT/.github/scripts/tests/fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }

# Expect: only app "alpha" when only apps/alpha changed
out=$(BASE_REF=fake HEAD_REF=fake CHANGED_FILES_FILE=<(printf '%s\n' 'apps/alpha/cloudrun/main.tf') \
  FIXTURE_ROOT="$FIX" "$SCRIPT" 2>/dev/null) || true
echo "$out" | jq -e '.[] | select(.app=="alpha")' >/dev/null || fail "alpha not detected"
echo "$out" | jq -e 'map(.app) | index("beta")' >/dev/null && fail "beta should be absent" || true

# Expect: module change fans out to consumers
out=$(BASE_REF=fake HEAD_REF=fake CHANGED_FILES_FILE=<(printf '%s\n' 'modules/cloudrun-service/main.tf') \
  FIXTURE_ROOT="$FIX" "$SCRIPT")
echo "$out" | jq -e 'map(.app) | index("alpha")' >/dev/null || fail "module fan-out missing alpha"
echo "$out" | jq -e 'map(.app) | index("beta")' >/dev/null || fail "module fan-out missing beta"

# Expect: empty when only docs change
out=$(BASE_REF=fake HEAD_REF=fake CHANGED_FILES_FILE=<(printf '%s\n' 'README.md') \
  FIXTURE_ROOT="$FIX" "$SCRIPT")
echo "$out" | jq -e '. == []' >/dev/null || fail "docs-only should be empty matrix"

echo "OK: detect-changed-apps tests passed"
```

Create fixtures:

```
.github/scripts/tests/fixtures/
  apps/
    alpha/
      app.yaml          # envs: [stawi-dev]
      cloudrun/main.tf  # source = "../../../modules/cloudrun-service"
    beta/
      app.yaml          # envs: [stawi-dev, stawi-prod]
      cloudrun/main.tf  # sources cloudrun-service and neon-database
  modules/
    cloudrun-service/main.tf
    neon-database/main.tf
  platforms/
    stawi-dev/main.tf
```

Fixture `apps/alpha/app.yaml`:

```yaml
name: alpha
envs: [stawi-dev]
neon:
  account: stawi-org
runtime: cloudrun
```

Fixture `apps/beta/app.yaml`:

```yaml
name: beta
envs: [stawi-dev, stawi-prod]
neon:
  account: stawi-labs
runtime: cloudrun
```

- [ ] **Step 2: Run tests — expect FAIL (script missing)**

```bash
chmod +x .github/scripts/tests/test-detect-changed-apps.sh
./.github/scripts/tests/test-detect-changed-apps.sh
```

Expected: FAIL (script not found or empty output)

- [ ] **Step 3: Implement `list-apps-using-module.sh`**

```bash
#!/usr/bin/env bash
# Usage: list-apps-using-module.sh <module-name> [repo-root]
# Prints app names (one per line) whose apps/*/cloudrun/**/*.tf contain modules/<module-name>
set -euo pipefail
MOD="${1:?module name required}"
ROOT="${2:-.}"
ROOT="$(cd "$ROOT" && pwd)"
# Skip _template
find "$ROOT/apps" -mindepth 2 -maxdepth 2 -type d -name cloudrun 2>/dev/null \
  | while read -r dir; do
      app="$(basename "$(dirname "$dir")")"
      [[ "$app" == _template ]] && continue
      if grep -Rqs "modules/${MOD}" "$dir" --include='*.tf'; then
        echo "$app"
      fi
    done | sort -u
```

- [ ] **Step 4: Implement `detect-changed-apps.sh`**

```bash
#!/usr/bin/env bash
# Outputs JSON array: [{"app":"x","env":"stawi-dev"}, ...]
# Env:
#   BASE_REF / HEAD_REF — git range (default: origin/main...HEAD)
#   CHANGED_FILES_FILE — if set, read paths from file (testing)
#   FIXTURE_ROOT — if set, treat as repo root instead of git root
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[[ -n "${FIXTURE_ROOT:-}" ]] && ROOT="$(cd "$FIXTURE_ROOT" && pwd)"

if [[ -n "${CHANGED_FILES_FILE:-}" ]]; then
  mapfile -t FILES < "$CHANGED_FILES_FILE"
else
  BASE="${BASE_REF:-origin/main}"
  HEAD="${HEAD_REF:-HEAD}"
  mapfile -t FILES < <(git -C "$ROOT" diff --name-only "$BASE"..."$HEAD" 2>/dev/null || true)
fi

declare -A APPS=()

add_app() {
  local a="$1"
  [[ -z "$a" || "$a" == _template ]] && return
  [[ -f "$ROOT/apps/$a/app.yaml" ]] || return
  APPS["$a"]=1
}

for f in "${FILES[@]:-}"; do
  if [[ "$f" =~ ^apps/([^/]+)/ ]]; then
    add_app "${BASH_REMATCH[1]}"
  elif [[ "$f" =~ ^modules/([^/]+)/ ]]; then
    mod="${BASH_REMATCH[1]}"
    while read -r a; do add_app "$a"; done < <("$ROOT/.github/scripts/list-apps-using-module.sh" "$mod" "$ROOT" 2>/dev/null || true)
    # when using FIXTURE_ROOT, list-apps path may need script from real repo:
    while read -r a; do add_app "$a"; done < <(bash -c '
      MOD="$0"; ROOT="$1"
      find "$ROOT/apps" -mindepth 2 -maxdepth 2 -type d -name cloudrun 2>/dev/null | while read -r dir; do
        app=$(basename $(dirname "$dir"))
        [[ "$app" == _template ]] && continue
        grep -Rqs "modules/${MOD}" "$dir" --include="*.tf" && echo "$app"
      done
    ' "$mod" "$ROOT")
  elif [[ "$f" =~ ^platforms/([^/]+)/ ]]; then
    plat="${BASH_REMATCH[1]}"
    for app_yaml in "$ROOT"/apps/*/app.yaml; do
      [[ -f "$app_yaml" ]] || continue
      app=$(basename "$(dirname "$app_yaml")")
      [[ "$app" == _template ]] && continue
      if grep -qE "envs:.*${plat}|- ${plat}" "$app_yaml" 2>/dev/null; then
        add_app "$app"
      fi
      # also if tf sources platforms/<plat>
      if grep -Rqs "platforms/${plat}" "$ROOT/apps/$app/cloudrun" --include='*.tf' 2>/dev/null; then
        add_app "$app"
      fi
    done
  fi
done

# Emit matrix
items=()
for app in "${!APPS[@]+"${!APPS[@]}"}"; do
  :
done
# bash 4+ iterate keys sorted
while IFS= read -r app; do
  [[ -z "$app" ]] && continue
  # read envs from app.yaml (yq if available, else grep)
  if command -v yq >/dev/null 2>&1; then
    mapfile -t envs < <(yq -r '.envs[]' "$ROOT/apps/$app/app.yaml")
  else
    mapfile -t envs < <(grep -E '^\s*-\s+stawi-' "$ROOT/apps/$app/app.yaml" | sed 's/.*- //')
  fi
  for env in "${envs[@]:-}"; do
    items+=("$(jq -nc --arg app "$app" --arg env "$env" '{app:$app,env:$env}')")
  done
done < <(printf '%s\n' "${!APPS[@]+"${!APPS[@]}"}" | sort)

if [[ ${#items[@]} -eq 0 ]]; then
  echo '[]'
else
  printf '%s\n' "${items[@]}" | jq -s .
fi
```

**Note for implementer:** keep the script idiomatic bash; fix array empty-key edge cases (`set -u`) so empty APPS prints `[]`. Prefer a cleaner rewrite if the draft above is fragile—tests define behaviour.

- [ ] **Step 5: Run tests — expect PASS**

```bash
chmod +x .github/scripts/*.sh .github/scripts/tests/*.sh
./.github/scripts/tests/test-detect-changed-apps.sh
```

Expected: `OK: detect-changed-apps tests passed`

- [ ] **Step 6: Commit**

```bash
git add .github/scripts
git commit -m "feat: path-based app change detection for independent CI"
```

---

### Task 3: `edge-contract` module

**Files:**
- Create: `modules/edge-contract/versions.tf`
- Create: `modules/edge-contract/variables.tf`
- Create: `modules/edge-contract/main.tf`
- Create: `modules/edge-contract/outputs.tf`

- [ ] **Step 1: Implement module (no cloud resources — pure data)**

`versions.tf`:

```hcl
terraform {
  required_version = ">= 1.8.0"
}
```

`variables.tf`:

```hcl
variable "env" {
  type        = string
  description = "stawi-dev | stawi-prod"
  validation {
    condition     = contains(["stawi-dev", "stawi-prod"], var.env)
    error_message = "env must be stawi-dev or stawi-prod"
  }
}
```

`main.tf`:

```hcl
locals {
  api_hosts = [
    "https://api.stawi.org",
    "https://api.stawi.dev",
  ]
  oauth_token_url = "https://oauth2.stawi.org/oauth2/token"
  cors_allow_origins = [
    "https://admin.stawi.org",
    "https://admin.stawi.dev",
    "https://admin-dev.stawi.dev",
    "https://admin-dev.stawi.org",
    "https://thesa.stawi.org",
    "https://thesa-dev.stawi.org",
    "http://localhost:5173",
  ]
  # Service env map injected into Cloud Run
  service_env = {
    OAUTH2_SERVICE_URI           = "https://oauth2.stawi.org"
    OAUTH2_AUDIENCE_BASE_URL     = "https://api.stawi.org"
    OAUTH2_CLIENT_ASSERTION_AUD  = local.oauth_token_url
    OTEL_EXPORTER_OTLP_ENDPOINT  = "https://otlp.nr-data.net" # override per platform if needed
    EDGE_ENV                     = var.env
  }
}
```

`outputs.tf`:

```hcl
output "api_hosts" {
  value = local.api_hosts
}
output "cors_allow_origins" {
  value = local.cors_allow_origins
}
output "service_env" {
  value = local.service_env
}
output "oauth_token_url" {
  value = local.oauth_token_url
}
```

- [ ] **Step 2: Validate**

```bash
cd modules/edge-contract && tofu init -backend=false && tofu validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add modules/edge-contract
git commit -m "feat(modules): add edge-contract defaults for public API/OAuth"
```

---

### Task 4: `neon-database` module

**Files:**
- Create: `modules/neon-database/versions.tf`
- Create: `modules/neon-database/variables.tf`
- Create: `modules/neon-database/main.tf`
- Create: `modules/neon-database/outputs.tf`

- [ ] **Step 1: Implement Neon project-per-app module**

`versions.tf`:

```hcl
terraform {
  required_version = ">= 1.8.0"
  required_providers {
    neon = {
      source  = "kislerdm/neon"
      version = ">= 0.6.0"
    }
  }
}
```

`variables.tf`:

```hcl
variable "app_name" {
  type        = string
  description = "Application name; becomes Neon project name prefix"
}
variable "region_id" {
  type        = string
  description = "Neon region id, e.g. aws-eu-central-1"
  default     = "aws-eu-central-1"
}
variable "pg_version" {
  type    = number
  default = 16
}
variable "database_name" {
  type    = string
  default = "app"
}
variable "role_name" {
  type    = string
  default = "app"
}
variable "history_retention_seconds" {
  type    = number
  default = 86400
}
```

`main.tf`:

```hcl
# Provider is configured in the app root (multi-account). This module
# uses the default neon provider configuration from the root module.
resource "neon_project" "this" {
  name       = var.app_name
  region_id  = var.region_id
  pg_version = var.pg_version

  history_retention_seconds = var.history_retention_seconds
}

resource "neon_role" "app" {
  project_id = neon_project.this.id
  branch_id  = neon_project.this.default_branch_id
  name       = var.role_name
}

resource "neon_database" "app" {
  project_id = neon_project.this.id
  branch_id  = neon_project.this.default_branch_id
  name       = var.database_name
  owner_name = neon_role.app.name
}
```

`outputs.tf`:

```hcl
output "project_id" {
  value = neon_project.this.id
}
output "branch_id" {
  value = neon_project.this.default_branch_id
}
output "database_name" {
  value = neon_database.app.name
}
output "role_name" {
  value = neon_role.app.name
}
# Connection URI — sensitive; prefer writing to Secret Manager in app root
output "connection_uri" {
  value     = neon_project.this.connection_uri
  sensitive = true
}
output "pooled_connection_uri" {
  description = "Prefer for Cloud Run (PgBouncer)"
  value       = try(neon_project.this.connection_uri_pooler, neon_project.this.connection_uri)
  sensitive   = true
}
```

**Implementer note:** Confirm attribute names against the installed `kislerdm/neon` provider docs at apply time (`connection_uri_pooler` vs endpoint host with `-pooler`). Adjust outputs to match the provider version locked in the template `versions.tf`.

- [ ] **Step 2: Validate syntax**

```bash
cd modules/neon-database && tofu init -backend=false && tofu validate
```

Expected: valid (provider download required).

- [ ] **Step 3: Commit**

```bash
git add modules/neon-database
git commit -m "feat(modules): neon-database one project per app"
```

---

### Task 5: `cloudrun-service` module

**Files:**
- Create: `modules/cloudrun-service/{versions,variables,main,outputs}.tf`

- [ ] **Step 1: Implement Cloud Run v2 service module**

`versions.tf`:

```hcl
terraform {
  required_version = ">= 1.8.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}
```

`variables.tf`:

```hcl
variable "name" {
  type = string
}
variable "project_id" {
  type = string
}
variable "region" {
  type = string
}
variable "image" {
  type = string
}
variable "env" {
  type        = map(string)
  default     = {}
  description = "Plain environment variables"
}
variable "secret_env" {
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default     = {}
  description = "Env vars sourced from Secret Manager"
}
variable "cpu" {
  type    = string
  default = "1"
}
variable "memory" {
  type    = string
  default = "512Mi"
}
variable "max_instance_count" {
  type    = number
  default = 10
}
variable "min_instance_count" {
  type    = number
  default = 0
}
variable "concurrency" {
  type    = number
  default = 80
}
variable "ingress" {
  type    = string
  default = "INGRESS_TRAFFIC_ALL"
}
variable "labels" {
  type    = map(string)
  default = {}
}
```

`main.tf` (shape — adjust resource names to google provider 5.x Cloud Run v2):

```hcl
resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = substr(replace(var.name, "_", "-"), 0, 28)
  display_name = "Cloud Run runtime for ${var.name}"
}

resource "google_cloud_run_v2_service" "this" {
  name     = var.name
  project  = var.project_id
  location = var.region
  ingress  = var.ingress
  labels   = var.labels

  template {
    service_account = google_service_account.runtime.email
    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }
    max_instance_request_concurrency = var.concurrency
    containers {
      image = var.image
      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }
      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }
      dynamic "env" {
        for_each = var.secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = env.value.version
            }
          }
        }
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
```

`outputs.tf`:

```hcl
output "uri" {
  value = google_cloud_run_v2_service.this.uri
}
output "service_account_email" {
  value = google_service_account.runtime.email
}
output "name" {
  value = google_cloud_run_v2_service.this.name
}
```

- [ ] **Step 2: Validate**

```bash
cd modules/cloudrun-service && tofu init -backend=false && tofu validate
```

- [ ] **Step 3: Commit**

```bash
git add modules/cloudrun-service
git commit -m "feat(modules): cloudrun-service reusable Cloud Run module"
```

---

### Task 6: Platform modules (`stawi-dev`, `stawi-prod`)

**Files:**
- Create: `platforms/stawi-dev/{main,outputs,versions}.tf`
- Create: `platforms/stawi-prod/{main,outputs,versions}.tf`

- [ ] **Step 1: Dev platform**

```hcl
# platforms/stawi-dev/main.tf
locals {
  env        = "stawi-dev"
  # Replace with real project IDs when GCP project for Cloud Run is ready
  project_id = "stawi-cloudrun-dev"
  region     = "europe-west1"
  labels = {
    environment = "dev"
    managed-by  = "cloud-deployment"
  }
}
```

```hcl
# platforms/stawi-dev/outputs.tf
output "env" { value = local.env }
output "project_id" { value = local.project_id }
output "region" { value = local.region }
output "labels" { value = local.labels }
```

- [ ] **Step 2: Prod platform** (same shape, `stawi-cloudrun-prod`, `environment = prod`)

- [ ] **Step 3: Commit**

```bash
git add platforms
git commit -m "feat: add stawi-dev and stawi-prod platform defaults"
```

**Implementer note:** project IDs are placeholders until real GCP projects exist; document in `docs/BACKEND.md` that platforms must be updated before first real apply.

---

### Task 7: App `_template` root

**Files:**
- Create: `apps/_template/app.yaml`
- Create: `apps/_template/cloudrun/versions.tf`
- Create: `apps/_template/cloudrun/backend.tf`
- Create: `apps/_template/cloudrun/variables.tf`
- Create: `apps/_template/cloudrun/main.tf`
- Create: `apps/_template/cloudrun/outputs.tf`
- Create: `apps/_template/cloudrun/envs/stawi-dev.tfvars`
- Create: `apps/_template/cloudrun/envs/stawi-prod.tfvars`

- [ ] **Step 1: Metadata**

```yaml
# apps/_template/app.yaml
name: REPLACE_ME
owners: []
envs:
  - stawi-dev
neon:
  account: stawi-org   # must exist in config/neon-accounts.yaml
runtime: cloudrun
```

- [ ] **Step 2: Thin OpenTofu root**

`backend.tf` — partial backend, key at init:

```hcl
terraform {
  backend "s3" {
    bucket                      = "cluster-tofu-state"
    region                      = "auto"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_lockfile                = true
    encrypt                     = true
  }
}
```

`versions.tf`:

```hcl
terraform {
  required_version = ">= 1.8.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    neon = {
      source  = "kislerdm/neon"
      version = ">= 0.6.0"
    }
  }
}
```

`variables.tf`:

```hcl
variable "app_name" { type = string }
variable "image" { type = string }
variable "neon_region_id" {
  type    = string
  default = "aws-eu-central-1"
}
variable "neon_api_key" {
  type      = string
  sensitive = true
}
```

`main.tf`:

```hcl
provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = module.platform.project_id
  region  = module.platform.region
}

module "platform" {
  source = "../../../platforms/stawi-dev"
}

module "edge" {
  source = "../../../modules/edge-contract"
  env    = module.platform.env
}

module "db" {
  source    = "../../../modules/neon-database"
  app_name  = var.app_name
  region_id = var.neon_region_id
}

resource "google_secret_manager_secret" "database_url" {
  project   = module.platform.project_id
  secret_id = "${var.app_name}-database-url"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = module.db.pooled_connection_uri
}

resource "google_secret_manager_secret_iam_member" "run_accessor" {
  project   = module.platform.project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.service.service_account_email}"
}

module "service" {
  source     = "../../../modules/cloudrun-service"
  name       = var.app_name
  project_id = module.platform.project_id
  region     = module.platform.region
  image      = var.image
  labels     = module.platform.labels
  env        = module.edge.service_env
  secret_env = {
    DATABASE_URL = {
      secret = google_secret_manager_secret.database_url.secret_id
    }
  }
  depends_on = [google_secret_manager_secret_iam_member.run_accessor]
}
```

**Circular dependency note:** `module.service` creates the SA used for secret IAM. Prefer either:

1. Create SA outside `cloudrun-service` and pass email in, or  
2. Two-phase: export SA from module, IAM after, and use `depends_on` with a split (SA-only submodule).

**Required fix in this task:** refactor `cloudrun-service` to accept optional `service_account_email` **or** output SA before service and grant secret access with a `google_service_account` resource in the root **before** the Cloud Run module. Recommended:

- Move `google_service_account` into the **app root** (or a tiny `runtime-sa` module), pass email into `cloudrun-service`.
- Update Task 5 module accordingly in the same commit if still local.

`envs/stawi-dev.tfvars`:

```hcl
app_name = "REPLACE_ME"
image    = "us-docker.pkg.dev/cloudrun/container/hello"
# neon_api_key from TF_VAR_neon_api_key / -var in CI
```

- [ ] **Step 3: Document that `_template` is skipped by CI detection**

Ensure `detect-changed-apps.sh` and `list-apps-using-module.sh` ignore `_template` (already in Task 2).

- [ ] **Step 4: `tofu validate` with backend=false**

```bash
cd apps/_template/cloudrun
tofu init -backend=false
tofu validate
```

- [ ] **Step 5: Commit**

```bash
git add apps/_template modules/cloudrun-service
git commit -m "feat: app template composing Cloud Run + Neon modules"
```

---

### Task 8: Reusable workflow `app-tofu.yml` + plan/apply

**Files:**
- Create: `.github/workflows/app-tofu.yml`
- Create: `.github/workflows/app-plan.yml`
- Create: `.github/workflows/app-apply.yml`

- [ ] **Step 1: Reusable workflow**

```yaml
# .github/workflows/app-tofu.yml
name: app-tofu
on:
  workflow_call:
    inputs:
      app:  { required: true, type: string }
      env:  { required: true, type: string }
      mode: { required: true, type: string } # plan | apply
    secrets:
      R2_ACCOUNT_ID:        { required: true }
      R2_ACCESS_KEY_ID:     { required: true }
      R2_SECRET_ACCESS_KEY: { required: true }
      # Neon keys — job selects one via app.yaml
      NEON_API_KEY_STAWI_ORG:  { required: false }
      NEON_API_KEY_STAWI_LABS: { required: false }

jobs:
  run:
    runs-on: ubuntu-latest
    concurrency:
      group: cloud-deploy-${{ inputs.app }}-${{ inputs.env }}
      cancel-in-progress: false
    permissions:
      contents: read
      id-token: write
      pull-requests: write
    defaults:
      run:
        working-directory: apps/${{ inputs.app }}/cloudrun
    steps:
      - uses: actions/checkout@v5
      - uses: opentofu/setup-opentofu@v2
        with:
          tofu_version: "1.10.0"
      - name: Resolve Neon account + platform path
        id: meta
        working-directory: .
        run: |
          set -euo pipefail
          ACC=$(yq -r '.neon.account' "apps/${{ inputs.app }}/app.yaml")
          SECRET_NAME=$(yq -r ".accounts[\"${ACC}\"].api_key_secret" config/neon-accounts.yaml)
          echo "neon_account=${ACC}" >> "$GITHUB_OUTPUT"
          echo "neon_secret_name=${SECRET_NAME}" >> "$GITHUB_OUTPUT"
          # Platform source: apps use platforms/<env> — validate env is listed
          yq -r '.envs[]' "apps/${{ inputs.app }}/app.yaml" | grep -qx "${{ inputs.env }}"
      - name: Export Neon API key
        env:
          NEON_API_KEY_STAWI_ORG: ${{ secrets.NEON_API_KEY_STAWI_ORG }}
          NEON_API_KEY_STAWI_LABS: ${{ secrets.NEON_API_KEY_STAWI_LABS }}
        run: |
          set -euo pipefail
          name="${{ steps.meta.outputs.neon_secret_name }}"
          val="${!name:-}"
          if [[ -z "$val" ]]; then
            echo "::error::Missing secret $name for Neon account ${{ steps.meta.outputs.neon_account }}"
            exit 1
          fi
          echo "::add-mask::$val"
          echo "TF_VAR_neon_api_key=$val" >> "$GITHUB_ENV"
      - name: Configure R2 credentials for backend
        env:
          R2_ACCOUNT_ID: ${{ secrets.R2_ACCOUNT_ID }}
        run: |
          echo "AWS_ACCESS_KEY_ID=${{ secrets.R2_ACCESS_KEY_ID }}" >> "$GITHUB_ENV"
          echo "AWS_SECRET_ACCESS_KEY=${{ secrets.R2_SECRET_ACCESS_KEY }}" >> "$GITHUB_ENV"
          echo "AWS_EC2_METADATA_DISABLED=true" >> "$GITHUB_ENV"
          echo "AWS_REGION=auto" >> "$GITHUB_ENV"
      # TODO(real pilot): google-github-actions/auth@v2 with WIF before tofu
      - name: Tofu init
        env:
          R2_ACCOUNT_ID: ${{ secrets.R2_ACCOUNT_ID }}
        run: |
          set -euo pipefail
          ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
          KEY="cloud-deployment/apps/${{ inputs.app }}/${{ inputs.env }}/terraform.tfstate"
          tofu init \
            -backend-config="key=${KEY}" \
            -backend-config="endpoints={s3=\"${ENDPOINT}\"}"
      - name: Select platform module for env
        run: |
          set -euo pipefail
          # Template uses platforms/stawi-dev hard-coded; real apps should use
          # a variable or symlink pattern. For v1: sed-replace is forbidden;
          # require main.tf to source ../../../platforms/${env} via:
          #   source = "../../../platforms/${var.platform}"
          # Ensure template uses variable platform = env name.
          true
      - name: Tofu plan
        if: inputs.mode == 'plan'
        run: |
          tofu plan \
            -var-file="envs/${{ inputs.env }}.tfvars" \
            -var="app_name=${{ inputs.app }}" \
            -out=tfplan
      - name: Upload plan
        if: inputs.mode == 'plan'
        uses: actions/upload-artifact@v4
        with:
          name: plan-${{ inputs.app }}-${{ inputs.env }}
          path: apps/${{ inputs.app }}/cloudrun/tfplan
      - name: Tofu apply
        if: inputs.mode == 'apply'
        run: |
          tofu apply -auto-approve \
            -var-file="envs/${{ inputs.env }}.tfvars" \
            -var="app_name=${{ inputs.app }}"
```

**Required template fix in same task:** `module "platform"` must use:

```hcl
variable "platform" { type = string }
module "platform" {
  source = "../../../platforms/${var.platform}"
}
```

And CI passes `-var="platform=${{ inputs.env }}"`.

- [ ] **Step 2: `app-plan.yml`**

```yaml
name: app-plan
on:
  pull_request:
    paths:
      - 'apps/**'
      - 'modules/**'
      - 'platforms/**'
      - 'config/**'
      - '.github/scripts/**'
      - '.github/workflows/app-*.yml'
  workflow_dispatch:
    inputs:
      app: { required: false, type: string, default: '' }
      env: { required: false, type: string, default: '' }

permissions:
  contents: read
  id-token: write
  pull-requests: write

jobs:
  detect:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.d.outputs.matrix }}
      nonempty: ${{ steps.d.outputs.nonempty }}
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
      - name: Install yq
        run: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq
      - id: d
        run: |
          set -euo pipefail
          if [[ -n "${{ inputs.app }}" ]]; then
            ENV="${{ inputs.env }}"
            [[ -n "$ENV" ]] || ENV=$(yq -r '.envs[0]' "apps/${{ inputs.app }}/app.yaml")
            MATRIX=$(jq -nc --arg a "${{ inputs.app }}" --arg e "$ENV" '[{app:$a,env:$e}]')
          else
            git fetch origin main 2>/dev/null || true
            MATRIX=$(BASE_REF=origin/main HEAD_REF=HEAD .github/scripts/detect-changed-apps.sh)
          fi
          echo "matrix=$(echo "$MATRIX" | jq -c .)" >> "$GITHUB_OUTPUT"
          if [[ "$MATRIX" == "[]" ]]; then
            echo "nonempty=false" >> "$GITHUB_OUTPUT"
          else
            echo "nonempty=true" >> "$GITHUB_OUTPUT"
          fi
          echo "Detected: $MATRIX"
  plan:
    needs: detect
    if: needs.detect.outputs.nonempty == 'true'
    strategy:
      fail-fast: false
      matrix:
        include: ${{ fromJson(needs.detect.outputs.matrix) }}
    uses: ./.github/workflows/app-tofu.yml
    with:
      app: ${{ matrix.app }}
      env: ${{ matrix.env }}
      mode: plan
    secrets: inherit
```

- [ ] **Step 3: `app-apply.yml`** (on push to `main`, same detect + `mode: apply`; optional GitHub Environment `production` for prod envs)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows apps/_template
git commit -m "feat(ci): per-app OpenTofu plan/apply with R2 state"
```

---

### Task 9: Operator docs + README refresh

**Files:**
- Create: `docs/ADDING_AN_APP.md`
- Create: `docs/MODULES.md`
- Modify: `README.md`

- [ ] **Step 1: Write ADDING_AN_APP.md**

Contents must include:

1. Copy `apps/_template` → `apps/<name>`
2. Set `app.yaml` (`name`, `envs`, `neon.account`)
3. Set `envs/*.tfvars` image
4. Ensure Neon account secret exists in GitHub
5. Open PR → only that app plans
6. Merge → only that app applies
7. Explicit: do not add Kubernetes YAML; cluster routes stay in `deployment.manifests`

- [ ] **Step 2: Write MODULES.md**

Document inputs/outputs for `edge-contract`, `neon-database`, `cloudrun-service`, platforms, multi-account Neon, R2 key pattern.

- [ ] **Step 3: Update README status** from “Architecture accepted” to “Scaffold in progress / ready for pilot”

- [ ] **Step 4: Commit**

```bash
git add docs README.md
git commit -m "docs: add app onboarding and module reference"
```

---

### Task 10: Lint/validate gate workflow

**Files:**
- Create: `.github/workflows/validate.yml`
- Create: `.tflint.hcl` (minimal)

- [ ] **Step 1: Validate workflow**

On PR:

- Run `./.github/scripts/tests/test-detect-changed-apps.sh`
- For each `modules/*` and `apps/_template/cloudrun`: `tofu init -backend=false && tofu validate`
- Fail if any `apps/**` contains `kind: HelmRelease` or `apiVersion: helm.toolkit.fluxcd.io` (guardrail)

Guardrail script step:

```bash
if grep -RInE 'HelmRelease|helm\.toolkit\.fluxcd\.io|kustomize\.toolkit\.fluxcd\.io' apps modules 2>/dev/null; then
  echo "Kubernetes/Flux manifests are forbidden in this repo" >&2
  exit 1
fi
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/validate.yml .tflint.hcl
git commit -m "ci: validate modules and forbid K8s manifests"
```

---

### Task 11: Smoke pilot checklist (manual / follow-up PR)

Not full production migration—verify the scaffolding works when credentials exist.

**Files:**
- Create: `docs/PILOT_CHECKLIST.md`

- [ ] **Step 1: Checklist content**

```markdown
# Pilot checklist

1. Create GitHub secrets: R2_*, NEON_API_KEY_STAWI_ORG (and labs if needed)
2. Set platforms/*/ project_id to real GCP projects
3. Configure WIF for Actions → Cloud Run deploy SA
4. Copy _template → apps/hello-edge (or real pilot name)
5. Open PR with only that app → confirm matrix is one cell
6. Plan succeeds against R2 key cloud-deployment/apps/hello-edge/stawi-dev/...
7. Merge apply; curl Cloud Run URI
8. Confirm Neon project created under the expected account
9. Confirm no files under deployment.manifests were required
```

- [ ] **Step 2: Commit**

```bash
git add docs/PILOT_CHECKLIST.md
git commit -m "docs: pilot go-live checklist for first edge app"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
|------------------|------|
| cloud.deployment owns Cloud Run + Neon only | Tasks 1–11; Task 10 guardrail |
| K8s only in deployment.manifests | Task 10 grep guard; docs |
| Per-app OpenTofu roots | Task 7 |
| R2 state per app/env | Tasks 1, 8 |
| Neon one project per app | Task 4 |
| Multi-account Neon | Tasks 1, 4, 8 |
| Independent CI / changed apps only | Tasks 2, 8 |
| Module impact fan-out | Task 2 |
| edge-contract / cloudrun / neon modules | Tasks 3–5 |
| Platforms stawi-dev/prod | Task 6 |
| Public edge only | Task 3 env defaults; no VPC modules |
| Greenfield first | Task 11 pilot |
| No monostack | Task 8 matrix |

## Execution notes

- Prefer **subagent-driven-development**: one task per subagent, commit per task.
- Do not apply real cloud resources until Task 11 credentials exist; Tasks 1–10 are repo-local + validate.
- If Neon provider attribute names differ, fix in Task 4/7 with `tofu providers schema -json` after init.
- OpenTofu version **1.10.0** matches `deployment.infra` workflows.

---

## Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-24-cloud-deployment-architecture.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — this session executes tasks with checkpoints  

Which approach?
