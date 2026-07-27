#!/usr/bin/env node
/**
 * Point stable hostnames at Cloud Run domain mappings (ghs.googlehosted.com).
 * DNS-only (grey) so Google can issue managed certs.
 *
 * Usage: CLOUDFLARE_API_TOKEN=… node scripts/ensure-cf-domain-mapping-dns.mjs
 */
const ZONE = process.env.CLOUDFLARE_ZONE_ID || "706bf604a333d866bb38c03bf643e79a";
const TOKEN = process.env.CLOUDFLARE_API_TOKEN;
const TARGET = "ghs.googlehosted.com";
const HOSTS = (process.env.DOMAIN_MAP_HOSTS || "accounts,oauth2,oauth2-w,authz,authz-w")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

if (!TOKEN) {
  console.error("CLOUDFLARE_API_TOKEN required");
  process.exit(1);
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
    throw new Error(`CF ${path} → ${res.status} ${JSON.stringify(body.errors || body)}`);
  }
  return body.result;
}

for (const name of HOSTS) {
  const fqdn = `${name}.stawi.org`;
  const list = await cf(
    `/zones/${ZONE}/dns_records?name=${encodeURIComponent(fqdn)}&per_page=50`,
  );
  const existing = (list || []).filter((r) =>
    ["A", "AAAA", "CNAME"].includes(String(r.type).toUpperCase()),
  );
  const comment = "Cloud Run domain mapping → ghs.googlehosted.com (grey)";
  const payload = {
    type: "CNAME",
    name,
    content: TARGET,
    proxied: false,
    ttl: 1,
    comment,
  };
  if (existing.length === 0) {
    console.log(`create CNAME ${fqdn} → ${TARGET} (DNS only)`);
    await cf(`/zones/${ZONE}/dns_records`, {
      method: "POST",
      body: JSON.stringify(payload),
    });
  } else {
    const primary = existing[0];
    console.log(
      `upsert CNAME ${fqdn} → ${TARGET} (was ${primary.type} proxied=${primary.proxied})`,
    );
    for (const r of existing.slice(1)) {
      await cf(`/zones/${ZONE}/dns_records/${r.id}`, { method: "DELETE" });
    }
    await cf(`/zones/${ZONE}/dns_records/${primary.id}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
  }
  // Delete worker routes so CF does not capture these hosts
  const routes = await cf(`/zones/${ZONE}/workers/routes`);
  for (const r of routes || []) {
    const pat = String(r.pattern || "");
    if (pat.startsWith(`${name}.stawi.org`) || pat === `${fqdn}/*`) {
      console.log(`delete worker route ${pat}`);
      await cf(`/zones/${ZONE}/workers/routes/${r.id}`, { method: "DELETE" });
    }
  }
}
console.log("Domain mapping DNS OK:", HOSTS.join(", "));
