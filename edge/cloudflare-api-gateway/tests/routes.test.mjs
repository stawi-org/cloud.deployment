import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(readFileSync(join(root, "config/routes.prod.json"), "utf8"));

function normalizePrefix(p) {
  if (!p || p[0] !== "/") return null;
  if (p.length > 1 && p.endsWith("/")) return p.slice(0, -1);
  return p;
}

function buildRoutes(cfg) {
  return (cfg.routes || [])
    .filter((r) => r.enabled !== false)
    .map((r) => ({ ...r, prefix: normalizePrefix(r.prefix) }))
    .filter((r) => r.prefix)
    .sort((a, b) => b.prefix.length - a.prefix.length);
}

function matchRoute(routes, pathname) {
  for (const r of routes) {
    if (pathname === r.prefix || pathname.startsWith(r.prefix + "/")) return r;
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

function originAllowed(origin, cfg) {
  const u = new URL(origin);
  if (u.protocol !== "https:") return false;
  const host = u.hostname.toLowerCase();
  const suffixes = cfg.origin_allowlist?.host_suffixes || [];
  if (suffixes.some((s) => host.endsWith(s))) return true;
  const extra = (cfg.origin_allowlist?.extra_hosts || []).map((h) => h.toLowerCase());
  return extra.includes(host);
}

describe("routes.prod.json", () => {
  it("has unique prefixes and ids", () => {
    const ids = new Set();
    const prefixes = new Set();
    for (const r of config.routes) {
      assert.ok(r.id);
      assert.equal(ids.has(r.id), false, `dup id ${r.id}`);
      ids.add(r.id);
      assert.equal(prefixes.has(r.prefix), false, `dup prefix ${r.prefix}`);
      prefixes.add(r.prefix);
    }
  });

  it("allowlists every enabled origin", () => {
    for (const r of config.routes) {
      if (r.enabled === false) continue;
      assert.ok(originAllowed(r.origin, config), r.id);
    }
  });
});

describe("routing semantics", () => {
  const routes = buildRoutes(config);

  it("matches /profile Connect paths", () => {
    const r = matchRoute(routes, "/profile/profile.v1.ProfileService/Get");
    assert.equal(r?.id, "profile");
    assert.equal(
      stripPrefix("/profile/profile.v1.ProfileService/Get", r.prefix, true),
      "/profile.v1.ProfileService/Get",
    );
  });

  it("matches exact prefix as /", () => {
    const r = matchRoute(routes, "/devices");
    assert.equal(r?.id, "devices");
    assert.equal(stripPrefix("/devices", r.prefix, true), "/");
  });

  it("does not match partial prefix names", () => {
    assert.equal(matchRoute(routes, "/profiles"), null);
    assert.equal(matchRoute(routes, "/device"), null);
  });

  it("prefers longer prefix when nested", () => {
    const nested = buildRoutes({
      routes: [
        { id: "a", prefix: "/pay", origin: "https://a.run.app", enabled: true },
        { id: "b", prefix: "/pay/checkout", origin: "https://b.run.app", enabled: true },
      ],
    });
    assert.equal(matchRoute(nested, "/pay/checkout/x")?.id, "b");
    assert.equal(matchRoute(nested, "/pay/other")?.id, "a");
  });
});
