#!/usr/bin/env node
/**
 * Cloudflare DNS for the public edge (no Google LB; no Google managed certs).
 *
 * - api.stawi.org: proxied A → 192.0.2.1 (Worker terminates; dummy origin)
 * - direct_cnames (pay, accounts, oauth2*, authz*): proxied CNAME → Cloud Run
 *   *.run.app host (TLS at Cloudflare Universal SSL; origin is run.app —
 *   pair with ensure-cf-origin-rules.mjs so Host header is the run.app hostname
 *   Cloud Run expects). This is CF direct mapping — works in any region.
 *
 * Env:
 *   CLOUDFLARE_API_TOKEN  (required)
 *   CLOUDFLARE_ZONE_ID    (default stawi.org)
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ZONE = process.env.CLOUDFLARE_ZONE_ID || "706bf604a333d866bb38c03bf643e79a";
const TOKEN = process.env.CLOUDFLARE_API_TOKEN;
const DUMMY_A = "192.0.2.1"; // RFC 5737 — Worker handles request before origin
const ZONE_SUFFIX = ".stawi.org";

if (!TOKEN) {
  console.error("CLOUDFLARE_API_TOKEN required");
  process.exit(1);
}

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(readFileSync(join(root, "config/routes.prod.json"), "utf8"));

function shortName(fqdn) {
  const f = String(fqdn).toLowerCase().replace(/\.$/, "");
  return f.endsWith(ZONE_SUFFIX) ? f.slice(0, -ZONE_SUFFIX.length) : f;
}

function originHost(originUrl) {
  return new URL(originUrl).hostname;
}

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
    const err = JSON.stringify(body.errors || body);
    throw new Error(`CF ${path} → ${res.status} ${err}`);
  }
  return body.result;
}

async function listTrafficRecords(fqdn) {
  const list = await cf(
    `/zones/${ZONE}/dns_records?name=${encodeURIComponent(fqdn)}&per_page=50`,
  );
  return (list || []).filter((r) =>
    ["A", "AAAA", "CNAME"].includes(String(r.type).toUpperCase()),
  );
}

async function ensureWorkerA(name) {
  const fqdn = `${name}${ZONE_SUFFIX}`;
  const existing = await listTrafficRecords(fqdn);
  const comment = "stawi Worker edge api.stawi.org only (docs/SSL_EDGE_POLICY.md)";

  if (existing.length === 0) {
    console.log(`create A ${fqdn} → ${DUMMY_A} (proxied, Worker)`);
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
    return;
  }

  const primary = existing.find((r) => r.type === "A") || existing[0];
  if (primary.type === "A" && primary.proxied && primary.content === DUMMY_A) {
    console.log(`ok ${fqdn} (proxied Worker A)`);
    return;
  }

  // Replace any grey LB / CNAME with Worker dummy A
  for (const r of existing) {
    if (r.id !== primary.id) {
      await cf(`/zones/${ZONE}/dns_records/${r.id}`, { method: "DELETE" });
    }
  }
  console.log(`upsert A ${fqdn} → ${DUMMY_A} proxied (was ${primary.type} ${primary.content})`);
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

async function ensureDirectCname(hostname, origin) {
  const name = shortName(hostname);
  const fqdn = `${name}${ZONE_SUFFIX}`;
  const target = originHost(origin);
  const comment = "stawi direct CNAME → Cloud Run (no Worker, no Google LB)";

  const existing = await listTrafficRecords(fqdn);

  if (existing.length === 0) {
    console.log(`create CNAME ${fqdn} → ${target} (proxied)`);
    await cf(`/zones/${ZONE}/dns_records`, {
      method: "POST",
      body: JSON.stringify({
        type: "CNAME",
        name,
        content: target,
        proxied: true,
        ttl: 1,
        comment,
      }),
    });
    return;
  }

  // Prefer one CNAME to run.app
  const primary = existing.find((r) => r.type === "CNAME") || existing[0];
  if (
    primary.type === "CNAME" &&
    primary.proxied &&
    String(primary.content).replace(/\.$/, "") === target
  ) {
    console.log(`ok ${fqdn} (proxied CNAME → ${target})`);
    return;
  }

  for (const r of existing) {
    if (r.id !== primary.id) {
      await cf(`/zones/${ZONE}/dns_records/${r.id}`, { method: "DELETE" });
    }
  }
  console.log(
    `upsert CNAME ${fqdn} → ${target} proxied (was ${primary.type} ${primary.content})`,
  );
  await cf(`/zones/${ZONE}/dns_records/${primary.id}`, {
    method: "PUT",
    body: JSON.stringify({
      type: "CNAME",
      name,
      content: target,
      proxied: true,
      ttl: 1,
      comment,
    }),
  });
}

// --- api Worker host ---
await ensureWorkerA(shortName(config.hostname || "api.stawi.org"));

// Hostnames served by this Worker (host_routes) need proxied dummy A, not CNAME.
const workerHostnames = new Set(
  (config.host_routes || [])
    .filter((h) => h?.enabled !== false && h?.hostname)
    .map((h) => String(h.hostname).toLowerCase().replace(/\.$/, "")),
);
for (const fqdn of workerHostnames) {
  await ensureWorkerA(shortName(fqdn));
}

// --- direct CNAME hosts (accounts, oauth2, …) — skip Worker-hosted hosts ---
for (const h of config.direct_cnames || []) {
  if (!h?.hostname || !h?.origin) continue;
  const fqdn = String(h.hostname).toLowerCase().replace(/\.$/, "");
  if (workerHostnames.has(fqdn)) {
    console.log(`skip direct CNAME ${fqdn} (Worker host_routes)`);
    continue;
  }
  await ensureDirectCname(h.hostname, h.origin);
}

console.log("DNS ensure complete.");
