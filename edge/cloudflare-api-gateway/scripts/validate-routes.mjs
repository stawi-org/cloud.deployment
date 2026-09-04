#!/usr/bin/env node
/**
 * Fail deploy if routes.prod.json is unsafe or inconsistent.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { validateCachePolicy } from "../src/edge-cache.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(readFileSync(join(root, "config/routes.prod.json"), "utf8"));

const errors = [];
const warnings = [];

if (config.version !== 1) errors.push("version must be 1");
if (!config.hostname || !config.hostname.includes(".")) {
  errors.push("hostname required");
}

const suffixes = config.origin_allowlist?.host_suffixes || [".a.run.app", ".run.app"];
const extra = (config.origin_allowlist?.extra_hosts || []).map((h) => h.toLowerCase());

function originOk(origin) {
  let u;
  try {
    u = new URL(origin);
  } catch {
    return false;
  }
  if (u.protocol !== "https:") return false;
  const host = u.hostname.toLowerCase();
  // Product APIs: Cloud Run only — never product *.stawi.org hosts.
  if (host.endsWith(".stawi.org") && host !== "api.stawi.org") {
    return false;
  }
  if (suffixes.some((s) => host.endsWith(s))) return true;
  return extra.includes(host);
}

if (extra.length) {
  warnings.push(
    `origin_allowlist.extra_hosts is non-empty (${extra.join(", ")}); product hosts should not be used — prefer *.run.app only`,
  );
}

const prefixes = new Map();
const ids = new Set();

// --- Host routes (accounts, oauth2) ---
const hostnames = new Set();
for (const r of config.host_routes || []) {
  if (!r.id) errors.push("host_route missing id");
  if (ids.has(r.id)) errors.push(`duplicate id: ${r.id}`);
  ids.add(r.id);
  if (!r.hostname || !r.hostname.includes(".")) {
    errors.push(`${r.id}: hostname required`);
  }
  const hn = String(r.hostname || "").toLowerCase();
  if (hostnames.has(hn)) errors.push(`duplicate hostname: ${hn}`);
  hostnames.add(hn);
  if (r.enabled === false) {
    warnings.push(`host_route ${r.id}: disabled`);
    continue;
  }
  if (!r.origin) {
    errors.push(`host_route ${r.id}: origin required when enabled`);
    continue;
  }
  if (!originOk(r.origin)) {
    errors.push(`host_route ${r.id}: origin not allowlisted: ${r.origin}`);
  }
  if (r.strip_prefix === true) {
    warnings.push(`host_route ${r.id}: strip_prefix true is unusual for host proxies`);
  }
  errors.push(...validateCachePolicy(r));
}

for (const r of config.routes || []) {
  if (!r.id) errors.push("route missing id");
  if (ids.has(r.id)) errors.push(`duplicate id: ${r.id}`);
  ids.add(r.id);

  if (!r.prefix || r.prefix[0] !== "/") {
    errors.push(`${r.id}: prefix must start with /`);
  }
  if (r.prefix === "/") {
    errors.push(`${r.id}: prefix must not be bare /`);
  }
  if (r.prefix?.length > 1 && r.prefix.endsWith("/")) {
    errors.push(`${r.id}: prefix must not end with / (use /profile not /profile/)`);
  }
  if (prefixes.has(r.prefix)) {
    errors.push(`duplicate prefix ${r.prefix}: ${prefixes.get(r.prefix)} and ${r.id}`);
  }
  prefixes.set(r.prefix, r.id);

  if (r.enabled === false) {
    warnings.push(`${r.id}: disabled`);
    continue;
  }
  if (!r.origin) {
    errors.push(`${r.id}: origin required when enabled`);
    continue;
  }
  if (!originOk(r.origin)) {
    errors.push(`${r.id}: origin not allowlisted: ${r.origin}`);
  }
  if (!r.service || !r.project) {
    warnings.push(`${r.id}: missing service/project metadata`);
  }

  errors.push(...validateCachePolicy(r));
  if (r.cache && r.public === false) {
    warnings.push(`${r.id}: cache block on a non-public route (only anonymous requests are cached)`);
  }

  if (r.docs) {
    if (r.docs.enabled !== false) {
      const op = r.docs.openapi_path || "/openapi.yaml";
      if (!op.startsWith("/")) {
        errors.push(`${r.id}: docs.openapi_path must start with /`);
      }
      if (!r.docs.title) {
        warnings.push(`${r.id}: docs.title missing (will use id)`);
      }
    }
  } else if (r.public !== false) {
    warnings.push(`${r.id}: no docs block — add docs.enabled + openapi_path for Scalar hub`);
  }
}

// Nested prefix ambiguity check (warn only — longest match handles it)
for (const a of prefixes.keys()) {
  for (const b of prefixes.keys()) {
    if (a !== b && b.startsWith(a + "/")) {
      warnings.push(`nested prefixes ${a} and ${b} — longest match wins at runtime`);
    }
  }
}

if (warnings.length) {
  console.log("Warnings:");
  for (const w of warnings) console.log("  -", w);
}

if (errors.length) {
  console.error("Validation FAILED:");
  for (const e of errors) console.error("  -", e);
  process.exit(1);
}

const enabled = (config.routes || []).filter((r) => r.enabled !== false).length;
console.log(`OK: ${enabled} enabled routes for ${config.hostname}`);
