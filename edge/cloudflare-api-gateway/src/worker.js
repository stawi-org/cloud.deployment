/**
 * stawi-api-gateway — path-based reverse proxy for api.stawi.org → Cloud Run.
 *
 * Safety model:
 *  - Only configured path prefixes are accepted (longest match wins).
 *  - Origins are fixed in config and re-checked against an allowlist at runtime.
 *  - Host header is forced to the origin host (required for Cloud Run *.run.app).
 *  - Not an open proxy: no user-controlled origin or arbitrary host rewrite.
 *
 * Extend: edit config/routes.prod.json, validate, deploy.
 */

import routesConfig from "../config/routes.prod.json";

const HOP_BY_HOP = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailers",
  "transfer-encoding",
  "upgrade",
  // Cloudflare / browser hop noise we regenerate
  "cf-connecting-ip",
  "cf-ipcountry",
  "cf-ray",
  "cf-visitor",
  "cdn-loop",
]);

/** @typedef {{ id: string, prefix: string, origin: string, strip_prefix?: boolean, enabled?: boolean, public?: boolean, service?: string }} Route */

function normalizePrefix(p) {
  if (!p || p[0] !== "/") return null;
  // collapse trailing slashes except root
  if (p.length > 1 && p.endsWith("/")) return p.slice(0, -1);
  return p;
}

function buildRouteTable(config) {
  const routes = (config.routes || [])
    .filter((r) => r && r.enabled !== false)
    .map((r) => ({
      ...r,
      prefix: normalizePrefix(r.prefix),
    }))
    .filter((r) => r.prefix && r.origin);

  // Longest prefix first so /profile/v2 would win over /profile if both exist.
  routes.sort((a, b) => b.prefix.length - a.prefix.length);
  return routes;
}

const ROUTES = buildRouteTable(routesConfig);
const HOSTNAME = routesConfig.hostname || "api.stawi.org";
const HEALTH = routesConfig.gateway?.health_path || "/_gateway/health";
const ROUTES_PATH = routesConfig.gateway?.routes_path || "/_gateway/routes";
const EXPOSE_ROUTES = routesConfig.gateway?.expose_route_list !== false;

function originAllowed(originUrl, config) {
  let u;
  try {
    u = new URL(originUrl);
  } catch {
    return false;
  }
  if (u.protocol !== "https:") return false;

  const host = u.hostname.toLowerCase();
  const suffixes = config.origin_allowlist?.host_suffixes || [".a.run.app", ".run.app"];
  if (suffixes.some((s) => host.endsWith(s))) return true;

  const extra = config.origin_allowlist?.extra_hosts || [];
  return extra.map((h) => h.toLowerCase()).includes(host);
}

/**
 * @param {string} pathname
 * @returns {Route | null}
 */
function matchRoute(pathname) {
  for (const r of ROUTES) {
    if (pathname === r.prefix || pathname.startsWith(r.prefix + "/")) {
      return r;
    }
  }
  return null;
}

/**
 * Strip configured prefix; never allow path escape outside "/".
 * /profile/foo → /foo ; /profile → /
 */
function stripPrefix(pathname, prefix, doStrip) {
  if (!doStrip) return pathname || "/";
  let rest = pathname.slice(prefix.length);
  if (rest === "") rest = "/";
  if (!rest.startsWith("/")) rest = "/" + rest;
  // block /../ style after strip
  const resolved = new URL(rest, "https://gateway.invalid").pathname;
  if (resolved.includes("\0")) return null;
  return resolved;
}

function copyRequestHeaders(req, originHost, publicHost) {
  const out = new Headers();
  for (const [k, v] of req.headers) {
    const key = k.toLowerCase();
    if (HOP_BY_HOP.has(key)) continue;
    if (key === "host") continue;
    // Drop absolute-form leftovers
    if (key === "x-forwarded-host" || key === "x-forwarded-proto") continue;
    out.append(k, v);
  }
  out.set("Host", originHost);
  out.set("X-Forwarded-Host", publicHost);
  out.set("X-Forwarded-Proto", "https");
  // Preserve client IP for app logs / rate limits
  const clientIp = req.headers.get("CF-Connecting-IP");
  if (clientIp) {
    out.set("X-Real-IP", clientIp);
    const prior = req.headers.get("X-Forwarded-For");
    out.set("X-Forwarded-For", prior ? `${prior}, ${clientIp}` : clientIp);
  }
  // Mark traffic as via stawi API gateway (debug / policy)
  out.set("X-Stawi-Gateway", "cloudflare-api-gateway");
  return out;
}

function jsonResponse(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body, null, 2) + "\n", {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-stawi-gateway": "cloudflare-api-gateway",
      ...extraHeaders,
    },
  });
}

function gatewayHealth() {
  return jsonResponse({
    ok: true,
    gateway: "cloudflare-api-gateway",
    hostname: HOSTNAME,
    routes: ROUTES.length,
    ts: new Date().toISOString(),
  });
}

function gatewayRoutes() {
  if (!EXPOSE_ROUTES) {
    return jsonResponse({ error: "not_found" }, 404);
  }
  return jsonResponse({
    hostname: HOSTNAME,
    routes: ROUTES.map((r) => ({
      id: r.id,
      prefix: r.prefix,
      service: r.service,
      public: r.public !== false,
      // intentional: do not expose full origin host details beyond service id in public list?
      // Operators need to debug — include origin host only (not secrets).
      origin_host: safeOriginHost(r.origin),
    })),
  });
}

function safeOriginHost(origin) {
  try {
    return new URL(origin).host;
  } catch {
    return null;
  }
}

/**
 * @param {Request} request
 * @param {ExecutionContext} _ctx
 */
async function handle(request, _ctx) {
  const url = new URL(request.url);

  // Only serve the configured public hostname (and workers.dev for previews).
  const host = url.hostname.toLowerCase();
  const allowedHost =
    host === HOSTNAME.toLowerCase() ||
    host.endsWith(".workers.dev") ||
    host === "localhost";
  if (!allowedHost) {
    return jsonResponse({ error: "host_not_allowed", host }, 421);
  }

  if (url.pathname === HEALTH || url.pathname === "/_gateway/healthz") {
    return gatewayHealth();
  }
  if (url.pathname === ROUTES_PATH) {
    return gatewayRoutes();
  }

  // No bare "/" product surface — avoid accidental default backends.
  if (url.pathname === "/" || url.pathname === "") {
    return jsonResponse(
      {
        error: "not_found",
        message: "Use a service path prefix, e.g. /profile/…",
        health: HEALTH,
        routes: EXPOSE_ROUTES ? ROUTES_PATH : undefined,
      },
      404,
    );
  }

  const route = matchRoute(url.pathname);
  if (!route) {
    return jsonResponse(
      {
        error: "no_route",
        path: url.pathname,
        message: "No API route registered for this path prefix.",
      },
      404,
    );
  }

  if (!originAllowed(route.origin, routesConfig)) {
    return jsonResponse(
      {
        error: "origin_not_allowlisted",
        route: route.id,
        message: "Route origin failed allowlist check (refusing to proxy).",
      },
      502,
    );
  }

  const stripped = stripPrefix(
    url.pathname,
    route.prefix,
    route.strip_prefix !== false,
  );
  if (stripped == null) {
    return jsonResponse({ error: "invalid_path" }, 400);
  }

  let originBase;
  try {
    originBase = new URL(route.origin);
  } catch {
    return jsonResponse({ error: "bad_origin_config", route: route.id }, 500);
  }

  const target = new URL(stripped + url.search, originBase);
  // Ensure we never leave the origin host
  if (target.hostname !== originBase.hostname) {
    return jsonResponse({ error: "origin_escape_blocked" }, 500);
  }

  const headers = copyRequestHeaders(request, originBase.host, HOSTNAME);

  /** @type {RequestInit} */
  const init = {
    method: request.method,
    headers,
    redirect: "manual",
  };

  // Body only when allowed (avoid GET/HEAD body quirks)
  if (request.method !== "GET" && request.method !== "HEAD") {
    init.body = request.body;
  }

  let upstream;
  try {
    upstream = await fetch(target.toString(), init);
  } catch (err) {
    return jsonResponse(
      {
        error: "upstream_unreachable",
        route: route.id,
        origin_host: originBase.host,
        detail: String(err && err.message ? err.message : err),
      },
      502,
    );
  }

  // Pass through response; add gateway marker (do not strip CORS from origin).
  const respHeaders = new Headers(upstream.headers);
  respHeaders.set("x-stawi-gateway", "cloudflare-api-gateway");
  respHeaders.set("x-stawi-route", route.id);

  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: respHeaders,
  });
}

export default {
  fetch: handle,
};
