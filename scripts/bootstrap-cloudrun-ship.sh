#!/usr/bin/env bash
# Bootstrap decentralized Cloud Run image shipping for a GCP project.
#
# Creates:
#   - cloudrun-ship@PROJECT SA (roles/run.developer + actAs runtime SAs)
#   - WIF OIDC provider github-ship (allowlisted GitHub repos only)
#   - workloadIdentityUser bindings per shipping repo
#
# Does NOT widen the tofu-deploy WIF provider (stays cloud.deployment-only).
#
# Usage:
#   ./scripts/bootstrap-cloudrun-ship.sh \
#     --project stawi-identity \
#     --project-number 721554040672 \
#     --runtime-sa identity-profile,identity-tenancy,identity-identity,identity-authentication \
#     --ship-repo antinvestor/service-profile,antinvestor/service-authentication,antinvestor/service-fintech

set -euo pipefail

PROJECT=""
PROJECT_NUM=""
POOL="github"
PROVIDER="github-ship"
SHIP_SA="cloudrun-ship"
RUNTIME_SAS=""
SHIP_REPOS=""

usage() {
  sed -n '2,20p' "$0"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --project-number) PROJECT_NUM="$2"; shift 2 ;;
    --pool) POOL="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --ship-sa) SHIP_SA="$2"; shift 2 ;;
    --runtime-sa) RUNTIME_SAS="$2"; shift 2 ;;
    --ship-repo) SHIP_REPOS="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -n "$PROJECT" && -n "$PROJECT_NUM" && -n "$RUNTIME_SAS" && -n "$SHIP_REPOS" ]] || usage

SHIP_EMAIL="${SHIP_SA}@${PROJECT}.iam.gserviceaccount.com"

echo "==> Ship SA ${SHIP_EMAIL}"
if ! gcloud iam service-accounts describe "$SHIP_EMAIL" --project="$PROJECT" &>/dev/null; then
  gcloud iam service-accounts create "$SHIP_SA" \
    --project="$PROJECT" \
    --display-name="Cloud Run image ship (decentralized GH releases)" \
    --description="Updates Cloud Run service/job images from service repos via WIF"
fi

for role in roles/run.developer roles/viewer; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:${SHIP_EMAIL}" \
    --role="$role" \
    --condition=None \
    --quiet >/dev/null
done

IFS=',' read -r -a RUNTIME_ARR <<< "$RUNTIME_SAS"
for sa in "${RUNTIME_ARR[@]}"; do
  sa=$(echo "$sa" | xargs)
  email="${sa}@${PROJECT}.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$email" --project="$PROJECT" &>/dev/null; then
    echo "  actAs $email"
    gcloud iam service-accounts add-iam-policy-binding "$email" \
      --project="$PROJECT" \
      --member="serviceAccount:${SHIP_EMAIL}" \
      --role="roles/iam.serviceAccountUser" \
      --quiet >/dev/null
  else
    echo "  skip missing runtime SA $email"
  fi
done

# CEL allowlist for OIDC provider
REPO_CEL=""
IFS=',' read -r -a REPO_ARR <<< "$SHIP_REPOS"
for r in "${REPO_ARR[@]}"; do
  r=$(echo "$r" | xargs)
  if [[ -n "$REPO_CEL" ]]; then
    REPO_CEL+=","
  fi
  REPO_CEL+="'${r}'"
done
ATTR_COND="assertion.repository in [${REPO_CEL}]"

echo "==> WIF provider ${PROVIDER} (${ATTR_COND})"
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER" \
  --location=global --workload-identity-pool="$POOL" --project="$PROJECT" &>/dev/null; then
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
    --project="$PROJECT" \
    --location=global \
    --workload-identity-pool="$POOL" \
    --display-name="GitHub Actions Cloud Run ship" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.actor=assertion.actor" \
    --attribute-condition="${ATTR_COND}"
else
  gcloud iam workload-identity-pools providers update-oidc "$PROVIDER" \
    --project="$PROJECT" \
    --location=global \
    --workload-identity-pool="$POOL" \
    --attribute-condition="${ATTR_COND}" \
    --quiet
fi

WIF_PROVIDER="projects/${PROJECT_NUM}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"

for r in "${REPO_ARR[@]}"; do
  r=$(echo "$r" | xargs)
  echo "  WIF bind $r → $SHIP_EMAIL"
  gcloud iam service-accounts add-iam-policy-binding "$SHIP_EMAIL" \
    --project="$PROJECT" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUM}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${r}" \
    --quiet >/dev/null
done

cat <<EOF

Bootstrapped Cloud Run ship for ${PROJECT}

  ship_service_account:       ${SHIP_EMAIL}
  workload_identity_provider: ${WIF_PROVIDER}

Wire service release.yml ship job with those values.
EOF
