#!/usr/bin/env bash
# Make antinvestor GHCR container packages public so Cloud Run can pull without AR mirrors.
#
# Prerequisites:
#   gh auth login  (or GH_TOKEN)
#   gh auth refresh -h github.com -s read:packages,write:packages
#   Token user must be org owner or package admin on antinvestor.
#
# Usage:
#   ./scripts/make-ghcr-public.sh
#   ./scripts/make-ghcr-public.sh service-trustage service-payment
set -euo pipefail

OWNER="${OWNER:-antinvestor}"

if ! command -v gh >/dev/null; then
  echo "ERROR: gh CLI required" >&2
  exit 1
fi

# Prefer GH_TOKEN; otherwise gh auth.
if [[ -z "${GH_TOKEN:-}" ]]; then
  export GH_TOKEN
  GH_TOKEN=$(gh auth token 2>/dev/null || true)
fi
if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "ERROR: no GH_TOKEN / gh auth session" >&2
  exit 1
fi

make_public() {
  local pkg="$1"
  local enc
  enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$pkg")
  local vis
  vis=$(gh api "orgs/${OWNER}/packages/container/${enc}" --jq .visibility 2>/dev/null || echo missing)
  if [[ "$vis" == "missing" ]]; then
    echo "SKIP missing: $pkg"
    return 0
  fi
  if [[ "$vis" == "public" ]]; then
    echo "OK already public: $pkg"
    return 0
  fi
  echo "==> publicize $pkg (was $vis)"
  for attempt in \
    "PUT orgs/${OWNER}/packages/container/${enc}/visibility" \
    "POST orgs/${OWNER}/packages/container/${enc}/visibility" \
    "PATCH orgs/${OWNER}/packages/container/${enc}"
  do
    method=${attempt%% *}
    path=${attempt#* }
    gh api --method "$method" "$path" -f visibility=public >/dev/null 2>&1 || true
    vis=$(gh api "orgs/${OWNER}/packages/container/${enc}" --jq .visibility 2>/dev/null || echo missing)
    if [[ "$vis" == "public" ]]; then
      echo "OK public: $pkg"
      return 0
    fi
  done
  curl -sS -X PATCH \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github.package-deletes-preview+json" \
    -H "Content-Type: application/json" \
    "https://api.github.com/orgs/${OWNER}/packages/container/${enc}" \
    -d '{"visibility":"public"}' >/dev/null || true
  vis=$(gh api "orgs/${OWNER}/packages/container/${enc}" --jq .visibility 2>/dev/null || echo missing)
  if [[ "$vis" == "public" ]]; then
    echo "OK public: $pkg"
    return 0
  fi
  echo "FAILED $pkg still ${vis}"
  echo "  UI: https://github.com/orgs/${OWNER}/packages/container/package/${pkg}/settings"
  echo "  → Danger Zone → Change visibility → Public"
  return 1
}

failed=0
if [[ $# -gt 0 ]]; then
  pkgs=("$@")
else
  mapfile -t pkgs < <(
    gh api --paginate "orgs/${OWNER}/packages?package_type=container&per_page=100" \
      --jq '.[] | select(.visibility=="private") | .name' 2>/dev/null || true
  )
  # Known monorepo images the list filter sometimes omits.
  for extra in service-authentication service-manufacturing service-payment \
    service-profile-devices service-profile-settings service-trustage \
    service-authentication-tenancy service-authentication-audit \
    service-profile service-files service-files-redirect \
    service-profile-geolocation service-fintech-identity \
    service-trustage-formstore service-trustage-queue; do
    pkgs+=("$extra")
  done
  mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
fi

for pkg in "${pkgs[@]}"; do
  pkg=$(echo "$pkg" | xargs)
  [[ -z "$pkg" ]] && continue
  make_public "$pkg" || failed=$((failed + 1))
done

if [[ "$failed" -gt 0 ]]; then
  echo ""
  echo "ERROR: ${failed} package(s) still private."
  echo "If API rejected changes, run:"
  echo "  gh auth refresh -h github.com -s read:packages,write:packages"
  echo "and re-run this script. Or use the package Settings UI links above."
  exit 1
fi
echo "All requested packages are public (anonymous Cloud Run pull OK)."
