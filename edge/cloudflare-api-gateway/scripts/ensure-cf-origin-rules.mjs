#!/usr/bin/env node
/**
 * Cloudflare Origin Rules: Host header + origin host = Cloud Run *.run.app
 * for every direct_cnames entry (pay, accounts, oauth2*, authz*).
 *
 * This is what makes CF direct mapping work without Google domain mapping:
 *   client → CF Universal SSL (Host: pay.stawi.org)
 *         → Origin Rule rewrites Host/origin to checkout-checkout-….run.app
 *         → Cloud Run serves the app (run.app cert; Full strict OK)
 *
 * Needs Zone permission for Rulesets (Zone.Zone Settings / Origin Rules edit).
 * Host-header override may also require a higher Cloudflare plan.
 *
 * Exit codes:
 *   0 — rules applied or nothing to do
 *   2 — auth/plan insufficient (caller may enable Worker host fallback)
 *   1 — unexpected error
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ZONE = process.env.CLOUDFLARE_ZONE_ID || "706bf604a333d866bb38c03bf643e79a";
const TOKEN = process.env.CLOUDFLARE_API_TOKEN;
const PHASE = "http_request_origin";
const RULESET_NAME = "stawi-cloud-run-origin-host";

if (!TOKEN) {
  console.error("CLOUDFLARE_API_TOKEN required");
  process.exit(1);
}

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(readFileSync(join(root, "config/routes.prod.json"), "utf8"));
const directs = (config.direct_cnames || []).filter((h) => h?.hostname && h?.origin);

if (directs.length === 0) {
  console.log("No direct_cnames — skip origin rules");
  process.exit(0);
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
    const err = body.errors || body;
    const e = new Error(`CF ${path} → ${res.status} ${JSON.stringify(err)}`);
    e.status = res.status;
    e.cf = err;
    throw e;
  }
  return body.result;
}

function originHost(originUrl) {
  return new URL(originUrl).hostname;
}

const rules = directs.map((h) => {
  const host = originHost(h.origin);
  const publicHost = String(h.hostname).toLowerCase().replace(/\.$/, "");
  return {
    description: `Cloud Run Host for ${publicHost}`,
    expression: `(http.host eq "${publicHost}")`,
    action: "route",
    enabled: true,
    action_parameters: {
      host_header: host,
      origin: { host },
    },
  };
});

try {
  const existing = await cf(`/zones/${ZONE}/rulesets`);
  const phaseSet = (existing || []).find((r) => r.phase === PHASE && r.kind === "zone");

  if (phaseSet?.id) {
    console.log(`update zone ruleset ${phaseSet.id} (${PHASE})`);
    const full = await cf(`/zones/${ZONE}/rulesets/${phaseSet.id}`);
    const keep = (full.rules || []).filter(
      (r) => !String(r.description || "").startsWith("Cloud Run Host for "),
    );
    await cf(`/zones/${ZONE}/rulesets/${phaseSet.id}`, {
      method: "PUT",
      body: JSON.stringify({
        name: full.name || RULESET_NAME,
        description: full.description || RULESET_NAME,
        kind: "zone",
        phase: PHASE,
        rules: [...keep, ...rules],
      }),
    });
  } else {
    console.log(`create zone ruleset ${PHASE}`);
    await cf(`/zones/${ZONE}/rulesets`, {
      method: "POST",
      body: JSON.stringify({
        name: RULESET_NAME,
        description: "Host header = Cloud Run *.run.app for direct_cnames (pay, accounts, oauth2, authz)",
        kind: "zone",
        phase: PHASE,
        rules,
      }),
    });
  }
  console.log("Origin rules OK:", directs.map((h) => h.hostname).join(", "));
  process.exit(0);
} catch (e) {
  const msg = String(e && e.message ? e.message : e);
  console.error(msg);
  if (e.status === 403 || msg.includes("10000") || msg.includes("Authentication") || msg.includes("permission") || msg.includes("plan")) {
    console.error(
      "::warning::Origin Host rewrite unavailable (token needs Zone Rulesets/Origin Rules edit; Host header override may need a higher CF plan). DNS CNAME alone is not enough for Cloud Run without Host rewrite.",
    );
    process.exit(2);
  }
  process.exit(1);
}
