/**
 * Per-route edge cache policy (routes[].cache / host_routes[].cache).
 *
 * Intended for anonymous, immutable public content such as the files
 * service's `/v1/public/media/...` routes. Pure helpers only — the Cache API
 * plumbing lives in worker.js so this module is unit-testable under Node.
 *
 * Config shape:
 *   "cache": {
 *     "paths": ["/v1/public/media/"],   // origin-relative prefixes (after strip_prefix)
 *     "ttl_seconds": 31536000,           // Cloudflare cacheTtl for the origin fetch
 *     "methods": ["GET", "HEAD"]         // optional, default GET+HEAD
 *   }
 */

export const CACHE_HEADER = "X-Gateway-Cache";
export const DEFAULT_CACHE_METHODS = ["GET", "HEAD"];
export const MAX_CACHE_TTL_SECONDS = 31536000;

const ALLOWED_METHODS = new Set(DEFAULT_CACHE_METHODS);

/** @returns {string[]} validation errors (empty when valid or absent) */
export function validateCachePolicy(route) {
  const errors = [];
  const c = route?.cache;
  if (c == null) return errors;
  const id = route.id || "?";
  if (typeof c !== "object" || Array.isArray(c)) {
    return [`${id}: cache must be an object`];
  }
  if (!Array.isArray(c.paths) || c.paths.length === 0) {
    errors.push(`${id}: cache.paths must be a non-empty array`);
  } else {
    for (const p of c.paths) {
      if (typeof p !== "string" || !p.startsWith("/")) {
        errors.push(`${id}: cache.paths entries must be strings starting with / (got ${JSON.stringify(p)})`);
      } else if (p === "/") {
        errors.push(`${id}: cache.paths must not contain bare / (would cache the whole service)`);
      }
    }
  }
  if (
    !Number.isInteger(c.ttl_seconds) ||
    c.ttl_seconds <= 0 ||
    c.ttl_seconds > MAX_CACHE_TTL_SECONDS
  ) {
    errors.push(`${id}: cache.ttl_seconds must be an integer in 1..${MAX_CACHE_TTL_SECONDS}`);
  }
  if (c.methods != null) {
    if (!Array.isArray(c.methods) || c.methods.length === 0) {
      errors.push(`${id}: cache.methods must be a non-empty array when set`);
    } else {
      for (const m of c.methods) {
        if (typeof m !== "string" || !ALLOWED_METHODS.has(m.toUpperCase())) {
          errors.push(`${id}: cache.methods may only contain GET/HEAD (got ${JSON.stringify(m)})`);
        }
      }
    }
  }
  return errors;
}

/**
 * @returns {{ paths: string[], ttlSeconds: number, methods: Set<string> } | null}
 *   null when the route has no (valid) cache block.
 */
export function compileCachePolicy(route) {
  if (route?.cache == null || validateCachePolicy(route).length) return null;
  const c = route.cache;
  return {
    paths: c.paths.slice(),
    ttlSeconds: c.ttl_seconds,
    methods: new Set((c.methods || DEFAULT_CACHE_METHODS).map((m) => m.toUpperCase())),
  };
}

/**
 * Should this request go through the edge cache?
 * Requires: policy, allowed method, no Authorization, origin path under a cache prefix.
 * @param {Request} request
 * @param {string} originPath  path after strip_prefix (origin-relative)
 */
export function cacheEligible(policy, request, originPath) {
  if (!policy) return false;
  if (!policy.methods.has(request.method)) return false;
  if (request.headers.has("Authorization")) return false;
  return policy.paths.some((p) => originPath === p || originPath.startsWith(p));
}

/**
 * Cache key: the full public URL (query included — width/height matter).
 * Always a GET so HEAD shares the stored GET entry. Conditional / Range
 * headers are forwarded so Cloudflare's cache.match can answer 304 / 206.
 * @param {Request} request
 */
export function cacheKey(request) {
  return new Request(request.url, { method: "GET", headers: request.headers });
}

/**
 * May this origin response be stored in the Cache API?
 * Only full 200 bodies to GET, explicitly public, no cookies, no Vary: *.
 * 206 (Range) and 304 are passed through uncached; Cloudflare's cache.match
 * serves ranges / conditionals from the stored 200 on later hits.
 * @param {Request} request @param {Response} response
 */
export function responseStorable(request, response) {
  if (request.method !== "GET") return false;
  if (response.status !== 200) return false;
  if (response.headers.has("Set-Cookie")) return false;
  if ((response.headers.get("Vary") || "").trim() === "*") return false;
  const cc = (response.headers.get("Cache-Control") || "").toLowerCase();
  if (!/\bpublic\b/.test(cc)) return false;
  if (/\b(private|no-store|no-cache)\b/.test(cc)) return false;
  return true;
}
