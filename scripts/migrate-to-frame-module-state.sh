#!/usr/bin/env bash
# One-time state relocation: hand-rolled modules → module.frame composition.
# Run from apps/<app>/cloudrun after tofu init, before apply, when main.tf uses
# module "frame" and state still has legacy addresses.
set -euo pipefail

if ! grep -qE 'module\s+"frame"' main.tf 2>/dev/null; then
  echo "no module.frame — skip state migration"
  exit 0
fi

mapfile -t STATE < <(tofu state list 2>/dev/null || true)
if [[ ${#STATE[@]} -eq 0 ]]; then
  echo "empty state — skip"
  exit 0
fi

# state list prints resource addresses only (never bare "module.foo").
# Match exact resource OR any resource under a module prefix.
in_state() {
  local needle="$1"
  local line
  for line in "${STATE[@]}"; do
    if [[ "$line" == "$needle" || "$line" == "$needle".* || "$line" == "$needle"[* ]]; then
      return 0
    fi
  done
  return 1
}

refresh_state() {
  mapfile -t STATE < <(tofu state list 2>/dev/null || true)
}

mv_if() {
  local from="$1" to="$2"
  if in_state "$from" && ! in_state "$to"; then
    echo "state mv $from → $to"
    if tofu state mv "$from" "$to"; then
      refresh_state
    else
      echo "warning: state mv failed: $from → $to (continuing)"
    fi
  elif in_state "$from" && in_state "$to"; then
    echo "skip $from (target $to already present)"
  fi
}

# Core resources (exact addresses)
mv_if 'data.google_project.this' 'module.frame.data.google_project.this'
mv_if 'data.google_cloud_run_v2_service.hydra' 'module.frame.data.google_cloud_run_v2_service.hydra'
mv_if 'data.google_cloud_run_v2_service.hydra_admin' 'module.frame.data.google_cloud_run_v2_service.hydra_admin[0]'
mv_if 'data.google_cloud_run_v2_service.keto_read' 'module.frame.data.google_cloud_run_v2_service.keto_read[0]'
mv_if 'data.google_cloud_run_v2_service.keto_write' 'module.frame.data.google_cloud_run_v2_service.keto_write[0]'
mv_if 'google_service_account.runtime' 'module.frame.google_service_account.runtime'
mv_if 'google_secret_manager_secret_iam_member.hydra_webhook_psk' \
  'module.frame.google_secret_manager_secret_iam_member.oauth_signer[0]'
mv_if 'google_service_account_iam_member.pubsub_push_token_creator' \
  'module.frame.google_service_account_iam_member.pubsub_push_token_creator[0]'
mv_if 'google_cloud_run_v2_service_iam_member.pubsub_push_invoker' \
  'module.frame.google_cloud_run_v2_service_iam_member.pubsub_push_invoker[0]'

# Whole modules (OpenTofu moves the entire module tree by prefix)
mv_if 'module.edge' 'module.frame.module.edge'
mv_if 'module.secrets' 'module.frame.module.secrets'
mv_if 'module.service' 'module.frame.module.service'
mv_if 'module.messaging' 'module.frame.module.messaging[0]'
mv_if 'module.keep_warm' 'module.frame.module.keep_warm[0]'

# DB / migrate (with or without count index)
if in_state 'module.db[0]'; then
  mv_if 'module.db[0]' 'module.frame.module.db[0]'
elif in_state 'module.db'; then
  mv_if 'module.db' 'module.frame.module.db[0]'
fi
if in_state 'module.migrate[0]'; then
  mv_if 'module.migrate[0]' 'module.frame.module.migrate[0]'
elif in_state 'module.migrate'; then
  mv_if 'module.migrate' 'module.frame.module.migrate[0]'
fi

echo "state migration pass complete"
echo "--- sample state (frame vs legacy) ---"
printf '%s\n' "${STATE[@]}" | grep -E '^(module\.frame|module\.(service|secrets|messaging|db|migrate|keep_warm))' | head -40 || true
