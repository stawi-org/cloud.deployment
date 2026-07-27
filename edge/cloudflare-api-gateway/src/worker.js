/**
 * stawi-api-gateway — Cloudflare public edge for api.stawi.org only.
 * See docs/SSL_EDGE_POLICY.md.
 *
 *  - api.stawi.org → path proxy + Scalar hub (this Worker)
 *  - accounts / oauth2* / authz* → CF orange CNAME → Cloud Run (not this Worker)
 *
 * Safety: origins only *.run.app; not an open proxy.
 * Extend: config/routes.prod.json → validate → deploy.
 */

import routesConfig from "../config/routes.prod.json";
import { isOpenAPIPath, rewriteOpenAPIServers } from "./openapi-rewrite.js";

const HOP_BY_HOP = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailers",
  "transfer-encoding",
  "upgrade",
  "cf-connecting-ip",
  "cf-ipcountry",
  "cf-ray",
  "cf-visitor",
  "cdn-loop",
]);

function normalizePrefix(p) {
  if (!p || p[0] !== "/") return null;
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

  routes.sort((a, b) => b.prefix.length - a.prefix.length);
  return routes;
}

const ROUTES = buildRouteTable(routesConfig);
const HOST_ROUTES = (() => {
  /** @type {Map<string, object>} */
  const m = new Map();
  for (const r of routesConfig.host_routes || []) {
    if (r.enabled === false || !r.hostname || !r.origin) continue;
    m.set(String(r.hostname).toLowerCase(), r);
  }
  return m;
})();
const HOSTNAME = routesConfig.hostname || "api.stawi.org";
const HEALTH = routesConfig.gateway?.health_path || "/_gateway/health";
const ROUTES_PATH = routesConfig.gateway?.routes_path || "/_gateway/routes";
const DOCS_META = routesConfig.gateway?.docs_path || "/_gateway/docs";
const HUB_PATHS = new Set(routesConfig.gateway?.hub_paths || ["/", "/docs"]);
const EXPOSE_ROUTES = routesConfig.gateway?.expose_route_list !== false;
const SCALAR = routesConfig.gateway?.scalar || {};
const ALLOWED_REQUEST_HOSTS = new Set([
  HOSTNAME.toLowerCase(),
  ...HOST_ROUTES.keys(),
]);

function originAllowed(originUrl, config) {
  let u;
  try {
    u = new URL(originUrl);
  } catch {
    return false;
  }
  if (u.protocol !== "https:") return false;
  const host = u.hostname.toLowerCase();
  // Origins must be Cloud Run — never product *.stawi.org hostnames.
  if (host.endsWith(".stawi.org")) {
    return false;
  }
  const suffixes = config.origin_allowlist?.host_suffixes || [".a.run.app", ".run.app"];
  if (suffixes.some((s) => host.endsWith(s))) return true;
  const extra = config.origin_allowlist?.extra_hosts || [];
  return extra.map((h) => h.toLowerCase()).includes(host);
}

function matchRoute(pathname) {
  for (const r of ROUTES) {
    if (pathname === r.prefix || pathname.startsWith(r.prefix + "/")) {
      return r;
    }
  }
  return null;
}

function stripPrefix(pathname, prefix, doStrip) {
  if (!doStrip) return pathname || "/";
  let rest = pathname.slice(prefix.length);
  if (rest === "") rest = "/";
  if (!rest.startsWith("/")) rest = "/" + rest;
  return new URL(rest, "https://gateway.invalid").pathname;
}

function copyRequestHeaders(req, originHost, publicHost) {
  const out = new Headers();
  for (const [k, v] of req.headers) {
    const key = k.toLowerCase();
    if (HOP_BY_HOP.has(key)) continue;
    if (key === "host") continue;
    if (key === "x-forwarded-host" || key === "x-forwarded-proto") continue;
    out.append(k, v);
  }
  out.set("Host", originHost);
  out.set("X-Forwarded-Host", publicHost);
  out.set("X-Forwarded-Proto", "https");
  const clientIp = req.headers.get("CF-Connecting-IP");
  if (clientIp) {
    out.set("X-Real-IP", clientIp);
    const prior = req.headers.get("X-Forwarded-For");
    out.set("X-Forwarded-For", prior ? `${prior}, ${clientIp}` : clientIp);
  }
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

function htmlResponse(html, status = 200) {
  return new Response(html, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=60",
      "x-stawi-gateway": "cloudflare-api-gateway",
      // Allow Scalar CDN + same-origin OpenAPI fetches
      "content-security-policy":
        "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://fonts.scalar.com; font-src 'self' https://fonts.scalar.com data:; img-src 'self' data: https:; connect-src 'self' https:; frame-ancestors 'none'",
    },
  });
}

function safeOriginHost(origin) {
  try {
    return new URL(origin).host;
  } catch {
    return null;
  }
}

/** Docs catalog for Scalar + /_gateway/docs */
function docsCatalog() {
  const sources = [];
  for (const r of ROUTES) {
    const docs = r.docs || {};
    if (docs.enabled === false) continue;
    // Skip non-public by default (Cloud Run IAM would block browser OpenAPI fetch)
    if (r.public === false && docs.include_authenticated !== true) continue;

    const openapiPath = docs.openapi_path || "/openapi.yaml";
    const pathPart = openapiPath.startsWith("/") ? openapiPath : `/${openapiPath}`;
    const title = docs.title || r.id;
    const slug = docs.slug || r.id;
    const serverUrl = `https://${HOSTNAME}${r.prefix}`;
    const url = `https://${HOSTNAME}${r.prefix}${pathPart}`;

    sources.push({
      id: r.id,
      title,
      slug,
      description: docs.description || "",
      url,
      openapi_path: pathPart,
      prefix: r.prefix,
      service: r.service,
      default: docs.default === true,
      servers: [{ url: serverUrl, description: "Stawi API gateway" }],
    });
  }
  // Ensure one default
  if (sources.length && !sources.some((s) => s.default)) {
    sources[0].default = true;
  }
  return sources;
}

function gatewayHealth() {
  return jsonResponse({
    ok: true,
    gateway: "cloudflare-api-gateway",
    hostname: HOSTNAME,
    path_routes: ROUTES.length,
    host_routes: [...HOST_ROUTES.keys()],
    docs: docsCatalog().length,
    hub: Array.from(HUB_PATHS),
    ssl_policy: "docs/SSL_EDGE_POLICY.md",
    ts: new Date().toISOString(),
  });
}

function gatewayRoutes() {
  if (!EXPOSE_ROUTES) return jsonResponse({ error: "not_found" }, 404);
  return jsonResponse({
    hostname: HOSTNAME,
    path_routes: ROUTES.map((r) => ({
      id: r.id,
      prefix: r.prefix,
      service: r.service,
      public: r.public !== false,
      origin_host: safeOriginHost(r.origin),
      docs: r.docs?.enabled !== false,
    })),
    host_routes: [...HOST_ROUTES.values()].map((r) => ({
      id: r.id,
      hostname: r.hostname,
      service: r.service,
      origin_host: safeOriginHost(r.origin),
      public: r.public !== false,
    })),
  });
}

function gatewayDocsMeta() {
  return jsonResponse({
    hostname: HOSTNAME,
    title: SCALAR.title || "Stawi API",
    sources: docsCatalog(),
  });
}

/**
 * Build Scalar multi-document config.
 * Each source is loaded via the gateway path so OpenAPI servers can be rewritten.
 */
function buildScalarConfig() {
  const sources = docsCatalog().map((s) => {
    const entry = {
      title: s.title,
      slug: s.slug,
      url: s.url,
      default: s.default || false,
    };
    return entry;
  });

  // Per-document server override via multi-configuration array
  const configs = docsCatalog().map((s) => ({
    title: s.title,
    slug: s.slug,
    url: s.url,
    default: s.default || false,
    servers: s.servers,
    // Prefer gateway same-origin; no external Scalar proxy required
    telemetry: false,
    hideClientButton: false,
    metaData: {
      title: `${SCALAR.title || "Stawi API"} · ${s.title}`,
    },
  }));

  return {
    theme: SCALAR.theme || "default",
    darkMode: SCALAR.dark_mode !== false,
    telemetry: false,
    // Prefer multi-config so each API gets correct servers for Try-it
    configs,
    // Fallback sources list if multi-config shape changes
    sources,
  };
}

function renderHubHtml() {
  const catalog = docsCatalog();
  const scalarCfg = buildScalarConfig();
  const title = SCALAR.title || "Stawi API";
  const cdn = SCALAR.cdn || "https://cdn.jsdelivr.net/npm/@scalar/api-reference";

  // Multi-configuration: one entry per service with servers rewrite for Try-it
  const createArg =
    catalog.length === 0
      ? JSON.stringify({
          content: {
            openapi: "3.1.0",
            info: {
              title,
              version: "0.0.0",
              description:
                "No OpenAPI-enabled routes yet. Add docs.enabled + openapi_path on a route in routes.prod.json.",
            },
            paths: {},
          },
        })
      : JSON.stringify(scalarCfg.configs);

  // Escape </script> in JSON
  const configJson = createArg.replace(/</g, "\\u003c");

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)}</title>
  <meta name="description" content="Stawi unified API documentation — all services under api.stawi.org" />
  <style>
    html, body { margin: 0; padding: 0; height: 100%; }
    #app { min-height: 100vh; }
  </style>
</head>
<body>
  <div id="app"></div>
  <script src="${escapeHtml(cdn)}"></script>
  <script>
    (function () {
      var configs = ${configJson};
      // Scalar: multi-document via createApiReference(selector, config | config[])
      Scalar.createApiReference('#app', configs);
    })();
  </script>
</body>
</html>`;
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function wantsHtml(request) {
  if (request.method !== "GET" && request.method !== "HEAD") return false;
  const accept = (request.headers.get("Accept") || "").toLowerCase();
  if (accept.includes("text/html")) return true;
  // Browsers often send */* ; treat no Accept as HTML for hub
  if (!accept || accept === "*/*") return true;
  return false;
}

/**
 * @param {Request} request
 * @param {{ id: string, origin: string, strip_prefix?: boolean, prefix?: string }} route
 * @param {URL} url
 * @param {string} publicHost  hostname clients used (for X-Forwarded-Host)
 * @param {{ rewriteOpenAPI?: boolean, openapiServerUrl?: string }} [opts]
 */
async function proxyToOrigin(request, route, url, publicHost, opts = {}) {
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

  const doStrip = route.strip_prefix === true;
  const prefix = route.prefix || "";
  const stripped = doStrip
    ? stripPrefix(url.pathname, prefix, true)
    : url.pathname || "/";
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
  if (target.hostname !== originBase.hostname) {
    return jsonResponse({ error: "origin_escape_blocked" }, 500);
  }

  const headers = copyRequestHeaders(request, originBase.host, publicHost);
  /** @type {RequestInit} */
  const init = {
    method: request.method,
    headers,
    redirect: "manual",
  };
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

  const respHeaders = new Headers(upstream.headers);
  respHeaders.set("x-stawi-gateway", "cloudflare-api-gateway");
  respHeaders.set("x-stawi-route", route.id);

  if (
    opts.rewriteOpenAPI &&
    request.method === "GET" &&
    upstream.ok &&
    isOpenAPIPath(stripped)
  ) {
    const raw = await upstream.text();
    const serverUrl = opts.openapiServerUrl || `https://${publicHost}${prefix}`;
    const rewritten = rewriteOpenAPIServers(
      raw,
      upstream.headers.get("content-type"),
      serverUrl,
    );
    respHeaders.set("content-type", rewritten.contentType);
    respHeaders.delete("content-length");
    if (!respHeaders.has("access-control-allow-origin")) {
      respHeaders.set("access-control-allow-origin", "*");
    }
    return new Response(rewritten.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: respHeaders,
    });
  }

  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: respHeaders,
  });
}

/**
 * @param {Request} request
 */
async function handle(request) {
  const url = new URL(request.url);
  const host = url.hostname.toLowerCase();
  const allowedHost =
    ALLOWED_REQUEST_HOSTS.has(host) ||
    host.endsWith(".workers.dev") ||
    host === "localhost";
  if (!allowedHost) {
    return jsonResponse({ error: "host_not_allowed", host }, 421);
  }

  // Optional host_routes (normally empty — only api.stawi.org is on this Worker).
  const hostRoute = HOST_ROUTES.get(host);
  if (hostRoute) {
    return proxyToOrigin(request, hostRoute, url, host, {
      rewriteOpenAPI: false,
    });
  }

  // Path gateway + Scalar hub (api.stawi.org only in prod).
  if (url.pathname === HEALTH || url.pathname === "/_gateway/healthz") {
    return gatewayHealth();
  }
  if (url.pathname === ROUTES_PATH) {
    return gatewayRoutes();
  }
  if (url.pathname === DOCS_META) {
    return gatewayDocsMeta();
  }

  if (HUB_PATHS.has(url.pathname) || url.pathname === "/docs/") {
    if (wantsHtml(request) || url.pathname.startsWith("/docs")) {
      return htmlResponse(renderHubHtml());
    }
    return gatewayDocsMeta();
  }

  const route = matchRoute(url.pathname);
  if (!route) {
    return jsonResponse(
      {
        error: "no_route",
        path: url.pathname,
        message: "No API route registered for this path prefix.",
        docs: "https://" + HOSTNAME + "/docs",
      },
      404,
    );
  }

  return proxyToOrigin(request, route, url, HOSTNAME, {
    rewriteOpenAPI: true,
    openapiServerUrl: `https://${HOSTNAME}${route.prefix}`,
  });
}

export default {
  fetch: handle,
};
