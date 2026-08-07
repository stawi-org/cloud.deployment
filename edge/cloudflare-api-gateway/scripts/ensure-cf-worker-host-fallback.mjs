#!/usr/bin/env node
/**
 * Free fallback when Origin Rule Host rewrite is unavailable:
 * attach Worker routes for CF-direct hosts and ensure Worker DNS (proxied A).
 * The api gateway Worker already proxies host_routes when configured; this script
 * only creates zone Worker routes + dummy A records pointing traffic at the Worker.
 *
 * Preferred path remains: orange CNAME → run.app + Origin Rules (no Worker).
 *
 * Skips short names in DOMAIN_MAP_HOSTS (default identity IAM hosts) so grey
 * domain-mapping DNS is not clobbered when hybrid edge is enabled.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";

const ZONE = process.env.CLOUDFLARE_ZONE_ID || "706bf604a333d866bb38c03bf643e79a";
const TOKEN = process.env.CLOUDFLARE_API_TOKEN;
const WORKER = process.env.WORKER_NAME || "stawi-api-gateway";
const DUMMY_A = "192.0.2.1";
const ZONE_SUFFIX = ".stawi.org";
const DOMAIN_MAPPED = new Set(
  (process.env.DOMAIN_MAP_HOSTS || "accounts,oauth2,oauth2-w,authz,authz-w")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean),
);

if (!TOKEN) {
  console.error("CLOUDFLARE_API_TOKEN required");
  process.exit(1);
}

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const configPath = join(root, "config/routes.prod.json");
const config = JSON.parse(readFileSync(configPath, "utf8"));
const directs = (config.direct_cnames || []).filter((h) => {
  const short = String(h.hostname || "")
    .toLowerCase()
    .replace(/\.$/, "")
    .replace(/\.stawi\.org$/, "");
  if (DOMAIN_MAPPED.has(short) || DOMAIN_MAPPED.has(h.id)) {
    console.log(`skip domain-mapped host ${h.hostname} (Worker fallback would clobber grey DNS)`);
    return false;
  }
  return true;
});

if (directs.length === 0) {
  console.log("No CF-direct hosts — nothing to fall back");
  process.exit(0);
}

// 1) Inject host_routes from direct_cnames so Worker can proxy
config.host_routes = directs.map((h) => ({
  id: h.id,
  hostname: h.hostname,
  service: h.id,
  origin: h.origin,
  strip_prefix: false,
  enabled: true,
  public: true,
  notes: "Free fallback Host proxy (Origin Rules unavailable)",
}));
writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
console.log("Wrote host_routes fallback into routes.prod.json (deploy-time only on runner)");

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

function shortName(fqdn) {
  const f = String(fqdn).toLowerCase().replace(/\.$/, "");
  return f.endsWith(ZONE_SUFFIX) ? f.slice(0, -ZONE_SUFFIX.length) : f;
}

// 2) DNS: proxied dummy A so Worker receives traffic
for (const h of directs) {
  const name = shortName(h.hostname);
  const fqdn = `${name}${ZONE_SUFFIX}`;
  const list = await cf(
    `/zones/${ZONE}/dns_records?name=${encodeURIComponent(fqdn)}&per_page=50`,
  );
  const existing = (list || []).filter((r) =>
    ["A", "AAAA", "CNAME"].includes(String(r.type).toUpperCase()),
  );
  const comment = "stawi free fallback: Worker host proxy (no Google LB)";
  if (existing.length === 0) {
    console.log(`create A ${fqdn} → ${DUMMY_A} proxied`);
    await cf(`/zones/${ZONE}/dns_records`, {
      method: "POST",
      body: JSON.stringify({
        type: "A",
        name,
        content: DUMMY_A,
        proxied: true,
        ttl: 1,
        comment,
      }),
    });
  } else {
    const primary = existing[0];
    console.log(`upsert A ${fqdn} → ${DUMMY_A} proxied (was ${primary.type})`);
    for (const r of existing.slice(1)) {
      await cf(`/zones/${ZONE}/dns_records/${r.id}`, { method: "DELETE" });
    }
    await cf(`/zones/${ZONE}/dns_records/${primary.id}`, {
      method: "PUT",
      body: JSON.stringify({
        type: "A",
        name,
        content: DUMMY_A,
        proxied: true,
        ttl: 1,
        comment,
      }),
    });
  }
}

// 3) Worker routes for each host
const routes = await cf(`/zones/${ZONE}/workers/routes`);
const have = new Set((routes || []).map((r) => String(r.pattern)));
for (const h of directs) {
  const pattern = `${String(h.hostname).toLowerCase().replace(/\.$/, "")}/*`;
  if (have.has(pattern)) {
    console.log(`ok route ${pattern}`);
    continue;
  }
  console.log(`create worker route ${pattern} → ${WORKER}`);
  await cf(`/zones/${ZONE}/workers/routes`, {
    method: "POST",
    body: JSON.stringify({ pattern, script: WORKER }),
  });
}

// 4) Redeploy Worker with injected host_routes
console.log("Redeploy Worker with host_routes fallback…");
const dep = spawnSync("npx", ["wrangler", "deploy"], {
  cwd: root,
  env: process.env,
  stdio: "inherit",
});
if (dep.status !== 0) process.exit(dep.status || 1);
console.log("Worker host fallback ready.");
