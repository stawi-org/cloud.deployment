#!/usr/bin/env bash
# Usage: list-apps-using-module.sh <module-name> [repo-root]
# Prints app names (one per line) whose apps/*/cloudrun/**/*.tf contain modules/<module-name>
set -euo pipefail

MOD="${1:?module name required}"
ROOT="${2:-.}"
ROOT="$(cd "$ROOT" && pwd)"

if [[ ! -d "$ROOT/apps" ]]; then
  exit 0
fi

find "$ROOT/apps" -mindepth 2 -maxdepth 2 -type d -name cloudrun 2>/dev/null \
  | while read -r dir; do
      app="$(basename "$(dirname "$dir")")"
      [[ "$app" == _template ]] && continue
      if grep -Rqs "modules/${MOD}" "$dir" --include='*.tf'; then
        echo "$app"
      fi
    done | sort -u
