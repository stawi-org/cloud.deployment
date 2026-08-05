#!/usr/bin/env bash
# Mirror a GHCR (or any) container image into a GCP Artifact Registry repo.
#
# Cloud Run cannot pull private/org-cached GHCR without extra credentials.
# Project-local AR is the reliable bootstrap + ship target.
#
# Usage:
#   ./scripts/mirror-ghcr-to-ar.sh \
#     --project stawi-identity \
#     --location europe-west9 \
#     --repo apps \
#     --src ghcr.io/antinvestor/service-authentication:v1.54.53 \
#     --name service-authentication \
#     --tag v1.54.53
#
# Multiple --src pairs:
#   --src ghcr.io/antinvestor/service-profile:v1.53.5 --name service-profile --tag v1.53.5
set -euo pipefail

PROJECT=""
LOCATION="europe-west9"
REPO="apps"
PLATFORM="linux/amd64"
SRCS=()
NAMES=()
TAGS=()

die() { echo "ERROR: $*" >&2; exit 1; }
say() { echo "==> $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --location) LOCATION="${2:?}"; shift 2 ;;
    --repo) REPO="${2:?}"; shift 2 ;;
    --platform) PLATFORM="${2:?}"; shift 2 ;;
    --src) SRCS+=("${2:?}"); shift 2 ;;
    --name) NAMES+=("${2:?}"); shift 2 ;;
    --tag) TAGS+=("${2:?}"); shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$PROJECT" ]] || die "--project required"
[[ ${#SRCS[@]} -gt 0 ]] || die "at least one --src required"
[[ ${#SRCS[@]} -eq ${#NAMES[@]} && ${#SRCS[@]} -eq ${#TAGS[@]} ]] \
  || die "each --src needs matching --name and --tag"

command -v gcloud >/dev/null || die "gcloud required"
command -v crane >/dev/null || die "crane required (go install github.com/google/go-containerregistry/cmd/crane@latest)"

if ! gcloud artifacts repositories describe "$REPO" \
    --project="$PROJECT" --location="$LOCATION" >/dev/null 2>&1; then
  say "creating Artifact Registry repo ${REPO} in ${LOCATION}"
  gcloud artifacts repositories create "$REPO" \
    --project="$PROJECT" \
    --location="$LOCATION" \
    --repository-format=docker \
    --description="Service images (mirrored from GHCR)" \
    --quiet
fi

PN=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
[[ -n "$PN" ]] || die "could not resolve project number"

# Pullers: Cloud Run agent + default compute + deploy/ship SAs (best-effort)
for MEMBER in \
  "serviceAccount:${PN}-compute@developer.gserviceaccount.com" \
  "serviceAccount:service-${PN}@serverless-robot-prod.iam.gserviceaccount.com" \
  "serviceAccount:tofu-deploy@${PROJECT}.iam.gserviceaccount.com" \
  "serviceAccount:cloudrun-ship@${PROJECT}.iam.gserviceaccount.com"; do
  gcloud artifacts repositories add-iam-policy-binding "$REPO" \
    --project="$PROJECT" --location="$LOCATION" \
    --member="$MEMBER" \
    --role="roles/artifactregistry.reader" \
    --quiet >/dev/null 2>&1 || true
done

gcloud auth configure-docker "${LOCATION}-docker.pkg.dev" --quiet >/dev/null

AR="${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}"
for i in "${!SRCS[@]}"; do
  src="${SRCS[$i]}"
  name="${NAMES[$i]}"
  tag="${TAGS[$i]}"
  dst="${AR}/${name}:${tag}"
  say "crane copy --platform=${PLATFORM} ${src} → ${dst}"
  crane copy --platform="$PLATFORM" "$src" "$dst"
  echo "  ok: ${dst}"
done

say "done — point Cloud Run tfvars image= at ${AR}/<name>:<tag>"
