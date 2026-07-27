#!/usr/bin/env node
/**
 * Delete Worker routes for hostnames that must NOT hit the api gateway Worker
 * (accounts / oauth2). Wrangler will not remove routes outside the token's
 * "All Zones" scope — this script uses the zone routes API instead.
 *
 * Env: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID, optional WORKER_NAME
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ZONE = process.env.CLOUDFLARE_ZONE_ID || "706bf604a333d866bb38c03bf643e79a";
const TOKEN = process.env.CLOUDFLARE_API_TOKEN;
const WORKER = process.env.WORKER_NAME || "stawi-api-gateway";

if (!TOKEN) {
  console.error("CLOUDFLARE_API_TOKEN required");
  process.exit(1);
}

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(readFileSync(join(root, "config/routes.prod.json"), "utf8"));
const dropHosts = new Set(
  (config.direct_cnames || []).map((h) => String(h.hostname).toLowerCase().replace(/\.$/, "")),
);

async function cf(path, opts = {}) {
  const res = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
    ...opts,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
      ...(opts.headers || {}),
    },
  });
  const body = await res.json();
  if (!body.success) {
    throw new Error(`CF ${path} → ${res.status} ${JSON.stringify(body.errors || body)}`);
  }
  return body.result;
}

const routes = await cf(`/zones/${ZONE}/workers/routes`);
let removed = 0;
for (const r of routes || []) {
  const pattern = String(r.pattern || "");
  // pattern like "accounts.stawi.org/*"
  const host = pattern.split("/")[0].toLowerCase();
  const script = r.script || r.script_name || "";
  if (!dropHosts.has(host)) continue;
  if (script && script !== WORKER) {
    console.log(`skip ${pattern} (script ${script})`);
    continue;
  }
  console.log(`delete worker route ${pattern} id=${r.id}`);
  await cf(`/zones/${ZONE}/workers/routes/${r.id}`, { method: "DELETE" });
  removed++;
}
console.log(`Removed ${removed} Worker route(s) for direct CNAME hosts.`);
