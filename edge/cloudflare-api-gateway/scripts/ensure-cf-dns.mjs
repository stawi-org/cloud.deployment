#!/usr/bin/env node
/**
 * Ensure Cloudflare DNS exists for Worker hostnames (orange / proxied).
 * Worker routes only fire when a zone DNS record exists.
 *
 * Creates/updates A records → 192.0.2.1 (TEST-NET, never reached; CF terminates
 * at the Worker). SSL: zone must be Full (strict).
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

if (!TOKEN) {
  console.error("CLOUDFLARE_API_TOKEN required");
  process.exit(1);
}

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(readFileSync(join(root, "config/routes.prod.json"), "utf8"));

const names = new Set([config.hostname, ...(config.host_routes || []).map((h) => h.hostname)]);
// short labels under zone
const shorts = [...names].map((fqdn) => {
  const f = String(fqdn).toLowerCase().replace(/\.$/, "");
  return f.endsWith(".stawi.org") ? f.slice(0, -".stawi.org".length) : f;
});

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

for (const name of shorts) {
  const list = await cf(
    `/zones/${ZONE}/dns_records?name=${encodeURIComponent(name + ".stawi.org")}&per_page=50`,
  );
  const existing = (list || []).filter((r) =>
    ["A", "AAAA", "CNAME"].includes(String(r.type).toUpperCase()),
  );

  if (existing.length === 0) {
    console.log(`create A ${name}.stawi.org → ${DUMMY_A} (proxied)`);
    await cf(`/zones/${ZONE}/dns_records`, {
      method: "POST",
      body: JSON.stringify({
        type: "A",
        name,
        content: DUMMY_A,
        proxied: true,
        ttl: 1,
        comment: "stawi-api-gateway Worker public edge (docs/SSL_EDGE_POLICY.md)",
      }),
    });
    continue;
  }

  // Prefer a single A record, proxied
  const primary = existing.find((r) => r.type === "A") || existing[0];
  if (primary.type === "A" && primary.proxied && primary.content === DUMMY_A) {
    console.log(`ok ${name}.stawi.org (proxied A ${DUMMY_A})`);
    continue;
  }

  // If already proxied to Cloudflare anycast (previous setup), leave it —
  // Worker routes still attach.
  if (primary.proxied) {
    console.log(
      `ok ${name}.stawi.org (existing proxied ${primary.type} ${primary.content})`,
    );
    continue;
  }

  // Grey A pointing at Google LB — flip to orange + dummy so Worker owns TLS.
  if (primary.type === "A") {
    console.log(
      `update ${name}.stawi.org ${primary.content} → ${DUMMY_A} proxied=true`,
    );
    await cf(`/zones/${ZONE}/dns_records/${primary.id}`, {
      method: "PUT",
      body: JSON.stringify({
        type: "A",
        name,
        content: DUMMY_A,
        proxied: true,
        ttl: 1,
        comment: "stawi-api-gateway Worker public edge (docs/SSL_EDGE_POLICY.md)",
      }),
    });
    continue;
  }

  // CNAME grey → replace with proxied A
  console.log(`replace ${name}.stawi.org ${primary.type} with proxied A`);
  await cf(`/zones/${ZONE}/dns_records/${primary.id}`, { method: "DELETE" });
  await cf(`/zones/${ZONE}/dns_records`, {
    method: "POST",
    body: JSON.stringify({
      type: "A",
      name,
      content: DUMMY_A,
      proxied: true,
      ttl: 1,
      comment: "stawi-api-gateway Worker public edge (docs/SSL_EDGE_POLICY.md)",
    }),
  });
}

console.log("DNS ensure complete.");
