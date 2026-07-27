#!/usr/bin/env bash
# scripts/audit-env-parity.sh
#
# End-to-end env key audit: Colony HelmRelease values.env + oauth2 chart
# vs live Cloud Run env, plus secret-catalog completeness vs SM existence.
# Never prints secret values.
#
# Usage:
#   ./scripts/audit-env-parity.sh
#   ./scripts/audit-env-parity.sh --json > /tmp/parity.json
#   ./scripts/audit-env-parity.sh --catalog-only
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFESTS="${MANIFESTS:-$HOME/code/stawi.org/deployment.manifests}"
JSON="false"
CATALOG_ONLY="false"
for arg in "$@"; do
  case "$arg" in
    --json) JSON="true" ;;
    --catalog-only) CATALOG_ONLY="true" ;;
  esac
done

python3 - "$ROOT" "$MANIFESTS" "$JSON" "$CATALOG_ONLY" <<'PY'
import json, os, re, subprocess, sys, yaml
from pathlib import Path

root, manifests, as_json, catalog_only = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3] == "true", sys.argv[4] == "true"

# Cloud Run service mapping: (service_name, gcp_project, colony_manifest_relpath_or_None)
# Keto deploys as -read/-write; hydra has admin sibling.
APPS = [
  ("identity-authentication", "stawi-identity", "namespaces/identity/authentication/service-authentication.yaml"),
  ("identity-tenancy", "stawi-identity", "namespaces/identity/tenancy/service-tenancy.yaml"),
  ("identity-profile", "stawi-identity", "namespaces/identity/profile/service-profile.yaml"),
  ("identity-identity", "stawi-identity", "namespaces/identity/identity/service-identity.yaml"),
  ("identity-oauth2-hydra", "stawi-identity", None),  # dedicated chart; not colony frame env
  ("identity-authorization-keto-read", "stawi-identity", None),
  ("identity-authorization-keto-write", "stawi-identity", None),
  ("platform-devices", "stawi-platform", "namespaces/platform/devices/service-devices.yaml"),
  ("platform-files", "stawi-platform", "namespaces/platform/files/service-files.yaml"),
  ("platform-settings", "stawi-platform", "namespaces/platform/settings/service-settings.yaml"),
  ("platform-geolocation", "stawi-platform", "namespaces/platform/geolocation/service-geolocation.yaml"),
  ("operations-audit", "stawi-identity", "namespaces/operations/audit/service-audit.yaml"),
  ("operations-redirect", "stawi-identity", "namespaces/operations/redirect/service-redirect.yaml"),
  ("operations-thesa", "stawi-identity", "namespaces/operations/thesa/service-thesa.yaml"),
  ("operations-formstore", "stawi-identity", "namespaces/operations/formstore/operations-formstore.yaml"),
  ("operations-queuestore", "stawi-identity", "namespaces/operations/queuestore"),  # may be dir
  ("operations-trustage", "stawi-identity", "namespaces/operations/trustage"),
]

# Infra translations — not expected as same key/value on Cloud Run
SKIP = {
  "EVENTS_QUEUE_URL", "NATS_CREDENTIALS_FILE",
  "DATABASE_USERNAME", "DATABASE_PASSWORD", "DATABASE_HOST", "DATABASE_NAME", "DATABASE_PORT",
  "CACHE_URI",  # mem:// on Cloud Run until Memorystore
  "VALKEY_CACHE_URL",
  "CACHE_CREDENTIALS_FILE",
  # Workload API / SPIFFE paths not used on Cloud Run OIDC path
  "PROFILE_SERVICE_WORKLOAD_API_TARGET_PATH",
  "TENANCY_SERVICE_WORKLOAD_API_TARGET_PATH",
  "NOTIFICATION_SERVICE_WORKLOAD_API_TARGET_PATH",
  "FILES_SERVICE_WORKLOAD_API_TARGET_PATH",
}

# Expected operator secret env keys per app (from secret-catalog + TF secret_env_extra)
EXPECTED_SECRET_ENVS = {
  "identity-authentication": {
    "DATABASE_URL", "CSRF_SECRET", "SECURE_COOKIE_HASH_KEY", "SECURE_COOKIE_BLOCK_KEY",
    "AUTH_PROVIDER_GOOGLE_CLIENT_ID", "AUTH_PROVIDER_GOOGLE_SECRET",
    "HYDRA_WEBHOOK_API_PSK", "OAUTH2_SIGNER_API_KEY",
  },
  "identity-profile": {
    "DATABASE_URL", "DEK_ACTIVE_KEY_ID", "DEK_ACTIVE_ENCRYPTION_TOKEN", "DEK_LOOKUP_TOKEN",
    "OAUTH2_SIGNER_API_KEY",
  },
  "identity-tenancy": {"DATABASE_URL", "OAUTH2_SIGNER_API_KEY"},
  "identity-identity": {"DATABASE_URL", "OAUTH2_SIGNER_API_KEY"},
  "identity-oauth2-hydra": {
    "DATABASE_URL", "DSN", "SECRETS_SYSTEM", "SECRETS_COOKIE",
    "WEBHOOK_BEARER_PSK", "OAUTH2_TOKEN_HOOK_AUTH_CONFIG",
  },
  "identity-authorization-keto-read": {"DATABASE_URL", "DSN", "REPLICA_DATABASE_URL"},
  "identity-authorization-keto-write": {"DATABASE_URL", "DSN", "REPLICA_DATABASE_URL"},
  "platform-devices": {
    "DATABASE_URL", "CLOUDFLARE_TURN_TOKEN_ID", "CLOUDFLARE_TURN_API_TOKEN", "OAUTH2_SIGNER_API_KEY",
  },
  "platform-files": {
    "DATABASE_URL", "ENCRYPTION_PHRASE", "S3_ENDPOINT", "S3_ACCESS_KEY_ID", "S3_ACCESS_KEY_SECRET",
    "OAUTH2_SIGNER_API_KEY",
  },
  "platform-settings": {"DATABASE_URL", "OAUTH2_SIGNER_API_KEY"},
  "platform-geolocation": {"DATABASE_URL", "OAUTH2_SIGNER_API_KEY"},
  "operations-audit": {"DATABASE_URL", "AUDIT_SIGNING_KEY", "OAUTH2_SIGNER_API_KEY"},
  "operations-redirect": {
    "DATABASE_URL", "ENCRYPTION_PHRASE", "ANALYTICS_USERNAME", "ANALYTICS_PASSWORD",
    "OAUTH2_SIGNER_API_KEY",
  },
  "operations-thesa": {
    "ANALYTICS_BACKEND_URL", "ANALYTICS_TOKEN", "OAUTH2_SIGNER_API_KEY",
  },
  "operations-formstore": {"DATABASE_URL", "OAUTH2_SIGNER_API_KEY"},
  "operations-queuestore": {"DATABASE_URL", "OAUTH2_SIGNER_API_KEY"},
  "operations-trustage": {"DATABASE_URL", "OAUTH2_SIGNER_API_KEY"},
}

# SM catalog IDs that must have ≥1 enabled version (project, secret_id)
CATALOG_SM = []
for cat_name, proj in [
  ("identity.yaml", "stawi-identity"),
  ("platform.yaml", "stawi-platform"),
  ("operations.yaml", "stawi-identity"),  # ops secrets staged on identity
]:
  cat_path = root / "config" / "secret-catalog" / cat_name
  if not cat_path.exists():
    continue
  data = yaml.safe_load(cat_path.read_text()) or {}
  for s in data.get("shared") or []:
    if s.get("required"):
      CATALOG_SM.append((proj, s["id"], "shared"))
  for app, body in (data.get("apps") or {}).items():
    for s in body.get("runtime_secrets") or []:
      if s.get("managed_by_tofu"):
        continue
      if s.get("required") is False:
        continue
      if s.get("shared"):
        continue
      CATALOG_SM.append((proj, s["id"], app))


def find_colony_path(rel):
  if not rel:
    return None
  p = manifests / rel
  if p.is_file():
    return p
  if p.is_dir():
    for cand in sorted(p.glob("*.yaml")):
      try:
        for d in yaml.safe_load_all(cand.read_text()):
          if isinstance(d, dict) and d.get("kind") == "HelmRelease":
            return cand
      except Exception:
        pass
  # fuzzy: search under parent
  parent = manifests / Path(rel).parts[0] / Path(rel).parts[1] if len(Path(rel).parts) >= 2 else None
  return None


def colony_envs(path: Path):
  envs = {}
  if not path or not path.exists():
    return envs
  for d in yaml.safe_load_all(path.read_text()):
    if not isinstance(d, dict) or d.get("kind") != "HelmRelease":
      continue
    values = (d.get("spec") or {}).get("values") or {}
    for item in values.get("env") or []:
      if not isinstance(item, dict) or not item.get("name"):
        continue
      name = item["name"]
      if "valueFrom" in item:
        envs[name] = {"kind": "secret", "present": True}
      else:
        envs[name] = {"kind": "literal", "present": True, "value": item.get("value")}
    o = values.get("oauth2") or {}
    if o.get("enabled"):
      envs["_oauth2"] = {
        "resourcePath": o.get("resourcePath"),
        "requestedAudiencePaths": o.get("requestedAudiencePaths") or [],
        "tokenEndpointAuthMethod": o.get("tokenEndpointAuthMethod"),
      }
    return envs
  return envs


def live_envs(project, service):
  try:
    out = subprocess.check_output(
      ["gcloud", "run", "services", "describe", service,
       f"--project={project}", "--region=europe-west1", "--format=json"],
      text=True, timeout=90, stderr=subprocess.DEVNULL,
    )
  except Exception as e:
    return None, str(e)
  d = json.loads(out)
  envs = {}
  for e in d["spec"]["template"]["spec"]["containers"][0].get("env") or []:
    n = e["name"]
    if "valueFrom" in e:
      envs[n] = {"kind": "secret", "present": True,
                 "secret": (e["valueFrom"].get("secretKeyRef") or {}).get("name")}
    else:
      envs[n] = {"kind": "literal", "present": True, "value": e.get("value")}
  status = d.get("status") or {}
  ready = next((c for c in (status.get("conditions") or []) if c.get("type") == "Ready"), {})
  return envs, {"ready": ready.get("status"), "reason": ready.get("reason", "")}


def sm_has_version(project, name):
  try:
    out = subprocess.check_output(
      ["gcloud", "secrets", "versions", "list", name,
       f"--project={project}", "--filter=state=ENABLED", "--limit=1",
       "--format=value(name)"],
      text=True, timeout=60, stderr=subprocess.DEVNULL,
    ).strip()
    return bool(out)
  except Exception:
    return False


# --- Catalog SM check ---
catalog_report = []
seen = set()
for proj, sid, owner in CATALOG_SM:
  key = (proj, sid)
  if key in seen:
    continue
  seen.add(key)
  ok = sm_has_version(proj, sid)
  catalog_report.append({
    "project": proj, "secret_id": sid, "owner": owner,
    "has_enabled_version": ok,
  })

if catalog_only:
  if as_json:
    print(json.dumps(catalog_report, indent=2))
  else:
    print("# Secret catalog vs GCP SM (no values)\n")
    for r in catalog_report:
      st = "OK" if r["has_enabled_version"] else "MISSING"
      print(f"  [{st}] {r['project']}/{r['secret_id']}  ({r['owner']})")
    bad = [r for r in catalog_report if not r["has_enabled_version"]]
    if bad:
      print(f"\nSummary: {len(bad)} catalog secrets missing versions")
      sys.exit(1)
    print(f"\nSummary: all {len(catalog_report)} required catalog secrets have versions.")
  sys.exit(0)

report = []
for svc, project, rel in APPS:
  path = find_colony_path(rel) if rel else None
  live, meta = live_envs(project, svc)
  if live is None:
    report.append({
      "app": svc, "project": project, "deployed": False,
      "error": f"not deployed or describe failed: {meta}",
      "ready_for_public_repo": True if svc.startswith("operations-") and svc != "operations-audit" else False,
      "note": "not yet on Cloud Run" if "not deployed" in str(meta).lower() or live is None else meta,
    })
    # undeployed ops apps are OK for public-repo (catalog+TF only)
    if svc.startswith("operations-") and svc != "operations-audit":
      report[-1]["ready_for_public_repo"] = True
      report[-1]["status"] = "NOT_DEPLOYED"
    continue

  c = colony_envs(path) if path else {}
  c_keys = {k for k in c if not k.startswith("_")}
  missing = sorted(k for k in c_keys if k not in live and k not in SKIP) if c_keys else []
  secret_ok = []
  secret_missing_mount = []
  for k in sorted(c_keys):
    if c[k].get("kind") != "secret":
      continue
    if k in SKIP:
      continue
    if k in live and live[k].get("kind") == "secret":
      secret_ok.append(k)
    else:
      secret_missing_mount.append(k)

  # Expected secret envs from catalog/TF
  expected = EXPECTED_SECRET_ENVS.get(svc, set())
  live_secret_keys = {k for k, v in live.items() if v.get("kind") == "secret"}
  expected_missing = sorted(expected - live_secret_keys)

  oauth = c.get("_oauth2") or {}
  live_aud = live.get("OAUTH2_RESOURCE_AUDIENCE", {}).get("value")
  live_client = live.get("OAUTH2_SERVICE_CLIENT_ID", {}).get("value")
  ready = (meta or {}).get("ready") if isinstance(meta, dict) else None

  ok = (
    len(missing) == 0
    and len(secret_missing_mount) == 0
    and len(expected_missing) == 0
    and ready == "True"
  )
  # Not-deployed sibling: already handled
  report.append({
    "app": svc,
    "project": project,
    "deployed": True,
    "ready": ready,
    "colony_env_count": len(c_keys),
    "live_env_count": len(live),
    "missing_env_keys": missing,
    "secret_mounts_ok": secret_ok,
    "secret_mounts_missing": secret_missing_mount,
    "expected_secret_envs_missing": expected_missing,
    "oauth2_resource_path": oauth.get("resourcePath"),
    "oauth2_live_resource_audience": live_aud,
    "oauth2_live_client_id": live_client,
    "ready_for_public_repo": len(missing) == 0 and len(secret_missing_mount) == 0 and len(expected_missing) == 0,
  })

# Catalog section always included
out = {
  "apps": report,
  "catalog_sm": catalog_report,
}

if as_json:
  print(json.dumps(out, indent=2))
else:
  print("# Env parity audit (Colony → Cloud Run + catalog SM)")
  print("# Secret values never printed.\n")
  for r in report:
    if not r.get("deployed"):
      print(f"## {r['app']} [NOT_DEPLOYED]")
      print(f"  {r.get('error', '')}\n")
      continue
    status = "OK" if r.get("ready_for_public_repo") and r.get("ready") == "True" else "GAPS"
    print(f"## {r['app']} [{status}] ready={r.get('ready')}")
    print(f"  colony_env={r.get('colony_env_count')} live_env={r.get('live_env_count')}")
    if r.get("oauth2_resource_path") or r.get("oauth2_live_resource_audience"):
      print(f"  oauth resource={r.get('oauth2_resource_path')} → {r.get('oauth2_live_resource_audience')}")
      print(f"  client_id={r.get('oauth2_live_client_id')}")
    if r.get("missing_env_keys"):
      print("  missing env keys:", ", ".join(r["missing_env_keys"]))
    if r.get("secret_mounts_missing"):
      print("  missing colony secret mounts:", ", ".join(r["secret_mounts_missing"]))
    if r.get("expected_secret_envs_missing"):
      print("  missing expected secret envs:", ", ".join(r["expected_secret_envs_missing"]))
    if r.get("secret_mounts_ok"):
      print("  colony secret mounts OK:", ", ".join(r["secret_mounts_ok"]))
    print()

  print("# Catalog secrets in GCP SM\n")
  for r in catalog_report:
    st = "OK" if r["has_enabled_version"] else "MISSING"
    print(f"  [{st}] {r['project']}/{r['secret_id']}  ({r['owner']})")

  bad_apps = [r["app"] for r in report if r.get("deployed") and not r.get("ready_for_public_repo")]
  bad_sm = [r["secret_id"] for r in catalog_report if not r["has_enabled_version"]]
  not_ready = [r["app"] for r in report if r.get("deployed") and r.get("ready") != "True"]
  print()
  if bad_apps or bad_sm or not_ready:
    if bad_apps:
      print(f"Summary: secret/env gaps on {', '.join(bad_apps)}")
    if not_ready:
      print(f"Summary: not Ready: {', '.join(not_ready)}")
    if bad_sm:
      print(f"Summary: SM missing versions: {', '.join(bad_sm)}")
    sys.exit(1)
  print("Summary: all deployed apps have expected secret mounts; catalog SM seeded.")
PY
