#!/usr/bin/env node
/**
 * Refresh origin URLs from live Cloud Run services (gcloud).
 * Usage:
 *   node scripts/refresh-origins.mjs
 *   GCLOUD_PROJECTS=stawi-identity,stawi-platform node scripts/refresh-origins.mjs
 *
 * Updates config/routes.prod.json in place when a matching service URL is found.
 * Falls back to https://{id}.stawi.org if Cloud Run is not readable.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { execFileSync } from "node:child_process";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const path = join(root, "config/routes.prod.json");
const config = JSON.parse(readFileSync(path, "utf8"));
const region = config.region || "europe-west9";

const projects = (
  process.env.GCLOUD_PROJECTS ||
  [...new Set((config.routes || []).map((r) => r.project).filter(Boolean))].join(",")
)
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

/** @type {Map<string, string>} service name → url */
const urls = new Map();

for (const project of projects) {
  try {
    const out = execFileSync(
      "gcloud",
      [
        "run",
        "services",
        "list",
        `--project=${project}`,
        `--region=${region}`,
        "--format=json(metadata.name,status.url)",
      ],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    );
    const list = JSON.parse(out || "[]");
    for (const s of list) {
      const name = s.metadata?.name;
      const url = s.status?.url;
      if (name && url) urls.set(name, url.replace(/\/$/, ""));
    }
    console.log(`project ${project}: ${list.length} services`);
  } catch (e) {
    console.warn(`project ${project}: skip (${e.stderr || e.message || e})`);
  }
}

let changed = 0;
for (const r of config.routes || []) {
  if (!r.service) continue;
  const live = urls.get(r.service);
  if (live && live !== r.origin) {
    console.log(`update ${r.id}: ${r.origin} → ${live}`);
    r.origin = live;
    changed++;
  } else if (!live && !r.origin) {
    const fallback = `https://${r.id}.stawi.org`;
    console.log(`fallback ${r.id}: ${fallback}`);
    r.origin = fallback;
    changed++;
  } else if (live) {
    console.log(`ok ${r.id}: ${live}`);
  } else {
    console.log(`keep ${r.id}: ${r.origin} (no live URL)`);
  }
}

writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
console.log(`Wrote ${path} (${changed} origin updates)`);
