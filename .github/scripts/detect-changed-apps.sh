#!/usr/bin/env bash
# Outputs JSON array: [{"app":"x","env":"stawi-dev"}, ...]
# Env:
#   BASE_REF / HEAD_REF — git range (default: origin/main...HEAD)
#   CHANGED_FILES_FILE — if set, read paths from file (testing)
#   FIXTURE_ROOT — if set, treat as repo root instead of git root
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Real repo root (where list-apps-using-module.sh lives)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Working root for apps/modules/platforms (fixture or real)
ROOT="$REPO_ROOT"
if [[ -n "${FIXTURE_ROOT:-}" ]]; then
  ROOT="$(cd "$FIXTURE_ROOT" && pwd)"
fi

LIST_APPS="$SCRIPT_DIR/list-apps-using-module.sh"

if [[ -n "${CHANGED_FILES_FILE:-}" ]]; then
  mapfile -t FILES < "$CHANGED_FILES_FILE"
else
  BASE="${BASE_REF:-origin/main}"
  HEAD="${HEAD_REF:-HEAD}"
  mapfile -t FILES < <(git -C "$ROOT" diff --name-only "${BASE}...${HEAD}" 2>/dev/null || true)
fi

declare -A APPS=()

add_app() {
  local a="$1"
  [[ -z "$a" || "$a" == _template ]] && return 0
  [[ -f "$ROOT/apps/$a/app.yaml" ]] || return 0
  APPS["$a"]=1
}

# Read env names from app.yaml (flow-style or block-style)
read_envs() {
  local yaml="$1"
  if command -v yq >/dev/null 2>&1; then
    yq -r '.envs[]?' "$yaml" 2>/dev/null || true
    return 0
  fi
  # Flow style: envs: [stawi-dev, stawi-prod]
  local line
  line="$(grep -E '^[[:space:]]*envs:[[:space:]]*\[' "$yaml" | head -1 || true)"
  if [[ -n "$line" ]]; then
    # shellcheck disable=SC2001
    echo "$line" \
      | sed -E 's/.*\[//; s/\].*//; s/,/\n/g' \
      | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^["'\'']//; s/["'\'']$//' \
      | grep -v '^$' || true
    return 0
  fi
  # Block style: envs:\n  - stawi-dev
  awk '
    /^[[:space:]]*envs:[[:space:]]*$/ { flag=1; next }
    flag && /^[[:space:]]*-[[:space:]]+/ {
      sub(/^[[:space:]]*-[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      gsub(/^["'\'']|["'\'']$/, "")
      print
      next
    }
    flag && /^[^[:space:]#]/ { exit }
  ' "$yaml"
}

# Collect apps from changed files
if [[ ${#FILES[@]} -gt 0 ]]; then
  for f in "${FILES[@]}"; do
    [[ -z "$f" ]] && continue
    if [[ "$f" =~ ^apps/([^/]+)/ ]]; then
      add_app "${BASH_REMATCH[1]}"
    elif [[ "$f" =~ ^modules/([^/]+)/ ]]; then
      mod="${BASH_REMATCH[1]}"
      while IFS= read -r a; do
        [[ -n "$a" ]] && add_app "$a"
      done < <("$LIST_APPS" "$mod" "$ROOT" 2>/dev/null || true)
    elif [[ "$f" =~ ^platforms/([^/]+)/ ]]; then
      plat="${BASH_REMATCH[1]}"
      shopt -s nullglob
      for app_yaml in "$ROOT"/apps/*/app.yaml; do
        app="$(basename "$(dirname "$app_yaml")")"
        [[ "$app" == _template ]] && continue
        # Apps listing this env in app.yaml envs
        while IFS= read -r env; do
          if [[ "$env" == "$plat" ]]; then
            add_app "$app"
            break
          fi
        done < <(read_envs "$app_yaml")
        # Also if tf sources platforms/<plat>
        if [[ -d "$ROOT/apps/$app/cloudrun" ]] \
          && grep -Rqs "platforms/${plat}" "$ROOT/apps/$app/cloudrun" --include='*.tf' 2>/dev/null; then
          add_app "$app"
        fi
      done
      shopt -u nullglob
    fi
  done
fi

# Emit matrix — safe with empty APPS under set -u
if [[ ${#APPS[@]} -eq 0 ]]; then
  echo '[]'
  exit 0
fi

items=()
while IFS= read -r app; do
  [[ -z "$app" ]] && continue
  while IFS= read -r env; do
    [[ -z "$env" ]] && continue
    items+=("$(jq -nc --arg app "$app" --arg env "$env" '{app:$app,env:$env}')")
  done < <(read_envs "$ROOT/apps/$app/app.yaml")
done < <(printf '%s\n' "${!APPS[@]}" | sort)

if [[ ${#items[@]} -eq 0 ]]; then
  echo '[]'
else
  printf '%s\n' "${items[@]}" | jq -s .
fi
