#!/usr/bin/env node
/**
 * Cloudflare Origin Rules: rewrite Host (and origin host) for direct CNAME
 * hosts so Cloud Run receives the *.run.app Host it expects.
 *
 * Requires a plan that allows Origin Rule "Host header" override (often
 * Enterprise; if the API rejects the rule, deploy fails with a clear error).
 *
 * Env:
 *   CLOUDFLARE_API_TOKEN  (required) — Zone Rulesets / Origin Rules edit
 *   CLOUDFLARE_ZONE_ID
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
    const err = JSON.stringify(body.errors || body, null, 2);
    throw new Error(`CF ${path} → ${res.status}\n${err}`);
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
      origin: {
        host,
      },
    },
  };
});

// List zone rulesets for this phase
const existing = await cf(`/zones/${ZONE}/rulesets`);
const phaseSet = (existing || []).find(
  (r) => r.phase === PHASE && r.kind === "zone",
);

const payload = {
  name: RULESET_NAME,
  description:
    "Send Host header = Cloud Run *.run.app for accounts/oauth2 CNAME origins",
  kind: "zone",
  phase: PHASE,
  rules,
};

if (phaseSet?.id) {
  console.log(`update zone ruleset ${phaseSet.id} (${PHASE})`);
  // GET full ruleset then replace our rules carefully — merge by description prefix
  const full = await cf(`/zones/${ZONE}/rulesets/${phaseSet.id}`);
  const keep = (full.rules || []).filter(
    (r) => !String(r.description || "").startsWith("Cloud Run Host for "),
  );
  await cf(`/zones/${ZONE}/rulesets/${phaseSet.id}`, {
    method: "PUT",
    body: JSON.stringify({
      name: full.name || RULESET_NAME,
      description: full.description || payload.description,
      kind: "zone",
      phase: PHASE,
      rules: [...keep, ...rules],
    }),
  });
} else {
  console.log(`create zone ruleset ${PHASE}`);
  await cf(`/zones/${ZONE}/rulesets`, {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

console.log("Origin rules ensure complete:", directs.map((h) => h.hostname).join(", "));
