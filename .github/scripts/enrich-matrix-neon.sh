#!/usr/bin/env bash
# Deprecated: use enrich-matrix-context.sh (SOPS credential model, no GH environments).
# Kept as a thin wrapper for any external callers.
set -euo pipefail
ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
exec "$ROOT/.github/scripts/enrich-matrix-context.sh" "$ROOT"
