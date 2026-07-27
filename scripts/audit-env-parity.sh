#!/usr/bin/env bash
# scripts/audit-env-parity.sh
#
# End-to-end env key audit: Colony HelmRelease values.env + oauth2 chart
# vs live Cloud Run env. Never prints secret values.
#
# Usage:
#   ./scripts/audit-env-parity.sh
#   ./scripts/audit-env-parity.sh --json > /tmp/parity.json
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFESTS="${MANIFESTS:-$HOME/code/stawi.org/deployment.manifests}"
JSON="false"
[[ "${1:-}" == "--json" ]] && JSON="true"

python3 - "$ROOT" "$MANIFESTS" "$JSON" <<'PY'
import json, os, re, subprocess, sys, yaml
from pathlib import Path

root, manifests, as_json = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3] == "true"

APPS = [
  ("identity-authentication", "stawi-identity", "namespaces/identity/authentication/service-authentication.yaml"),
  ("identity-tenancy", "stawi-identity", "namespaces/identity/tenancy/service-tenancy.yaml"),
  ("identity-profile", "stawi-identity", "namespaces/identity/profile/service-profile.yaml"),
  ("identity-identity", "stawi-identity", "namespaces/identity/identity/service-identity.yaml"),
  ("platform-devices", "stawi-platform", "namespaces/platform/devices/service-devices.yaml"),
  ("platform-files", "stawi-platform", "namespaces/platform/files/service-files.yaml"),
  ("platform-settings", "stawi-platform", "namespaces/platform/settings/service-settings.yaml"),
  ("platform-geolocation", "stawi-platform", "namespaces/platform/geolocation/service-geolocation.yaml"),
]

# Infra translations — not expected as same key/value
SKIP = {
  "EVENTS_QUEUE_URL", "NATS_CREDENTIALS_FILE",
  "DATABASE_USERNAME", "DATABASE_PASSWORD", "DATABASE_HOST", "DATABASE_NAME", "DATABASE_PORT",
  "CACHE_URI",  # mem:// on Cloud Run until Memorystore
}

def colony_envs(path: Path):
    envs = {}
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
    out = subprocess.check_output(
        ["gcloud", "run", "services", "describe", service,
         f"--project={project}", "--region=europe-west9", "--format=json"],
        text=True, timeout=90,
    )
    d = json.loads(out)
    envs = {}
    for e in d["spec"]["template"]["spec"]["containers"][0].get("env") or []:
        n = e["name"]
        if "valueFrom" in e:
            envs[n] = {"kind": "secret", "present": True,
                       "secret": (e["valueFrom"].get("secretKeyRef") or {}).get("name")}
        else:
            envs[n] = {"kind": "literal", "present": True, "value": e.get("value")}
    return envs

report = []
for svc, project, rel in APPS:
    path = manifests / rel
    if not path.exists():
        report.append({"app": svc, "error": f"missing colony path {rel}"})
        continue
    c = colony_envs(path)
    live = live_envs(project, svc)
    c_keys = {k for k in c if not k.startswith("_")}
    missing = sorted(k for k in c_keys if k not in live and k not in SKIP)
    # secrets present?
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
    oauth = c.get("_oauth2") or {}
    live_aud = live.get("OAUTH2_RESOURCE_AUDIENCE", {}).get("value")
    live_client = live.get("OAUTH2_SERVICE_CLIENT_ID", {}).get("value")
    report.append({
        "app": svc,
        "project": project,
        "colony_env_count": len(c_keys),
        "live_env_count": len(live),
        "missing_env_keys": missing,
        "secret_mounts_ok": secret_ok,
        "secret_mounts_missing": secret_missing_mount,
        "oauth2_resource_path": oauth.get("resourcePath"),
        "oauth2_live_resource_audience": live_aud,
        "oauth2_live_client_id": live_client,
        "ready_for_public_repo": len(missing) == 0 and len(secret_missing_mount) == 0,
    })

if as_json:
    print(json.dumps(report, indent=2))
else:
    print("# Env parity audit (Colony → Cloud Run)")
    print("# Secret values never printed.\n")
    for r in report:
        status = "OK" if r.get("ready_for_public_repo") else "GAPS"
        print(f"## {r['app']} [{status}]")
        if r.get("error"):
            print(f"  ERROR: {r['error']}\n")
            continue
        print(f"  colony_env={r['colony_env_count']} live_env={r['live_env_count']}")
        print(f"  oauth resource={r.get('oauth2_resource_path')} → {r.get('oauth2_live_resource_audience')}")
        print(f"  client_id={r.get('oauth2_live_client_id')}")
        if r["missing_env_keys"]:
            print("  missing env keys:", ", ".join(r["missing_env_keys"]))
        if r["secret_mounts_missing"]:
            print("  missing secret mounts:", ", ".join(r["secret_mounts_missing"]))
        if r["secret_mounts_ok"]:
            print("  secret mounts OK:", ", ".join(r["secret_mounts_ok"]))
        print()
    bad = [r["app"] for r in report if not r.get("ready_for_public_repo")]
    if bad:
        print(f"Summary: gaps on {', '.join(bad)}")
        sys.exit(1)
    print("Summary: all audited apps have colony env keys mounted (modulo intentional SKIP).")
PY
