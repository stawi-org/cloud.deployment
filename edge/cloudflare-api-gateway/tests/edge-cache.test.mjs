import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  cacheEligible,
  cacheKey,
  compileCachePolicy,
  responseStorable,
  validateCachePolicy,
} from "../src/edge-cache.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(readFileSync(join(root, "config/routes.prod.json"), "utf8"));

const filesCache = {
  id: "files",
  cache: { paths: ["/v1/public/media/"], ttl_seconds: 31536000, methods: ["GET", "HEAD"] },
};

describe("routes.prod.json cache blocks", () => {
  it("every cache block validates", () => {
    for (const r of [...(config.routes || []), ...(config.host_routes || [])]) {
      assert.deepEqual(validateCachePolicy(r), [], r.id);
    }
  });

  it("files route caches anonymous public media for a year", () => {
    const files = config.routes.find((r) => r.id === "files");
    assert.ok(files.cache, "files route must declare cache");
    assert.deepEqual(files.cache.paths, ["/v1/public/media/"]);
    assert.equal(files.cache.ttl_seconds, 31536000);
    assert.equal(files.strip_prefix, true);
  });
});

describe("validateCachePolicy", () => {
  it("accepts a route without cache and a valid block", () => {
    assert.deepEqual(validateCachePolicy({ id: "x" }), []);
    assert.deepEqual(validateCachePolicy(filesCache), []);
    assert.deepEqual(
      validateCachePolicy({ id: "x", cache: { paths: ["/a"], ttl_seconds: 60 } }),
      [],
    );
  });

  it("rejects missing/empty paths, bare /, relative paths", () => {
    assert.ok(validateCachePolicy({ id: "x", cache: { ttl_seconds: 1 } }).length);
    assert.ok(validateCachePolicy({ id: "x", cache: { paths: [], ttl_seconds: 1 } }).length);
    assert.ok(validateCachePolicy({ id: "x", cache: { paths: ["/"], ttl_seconds: 1 } }).length);
    assert.ok(validateCachePolicy({ id: "x", cache: { paths: ["v1"], ttl_seconds: 1 } }).length);
  });

  it("rejects bad ttl_seconds", () => {
    for (const ttl of [0, -1, 1.5, "60", 31536001, undefined]) {
      assert.ok(
        validateCachePolicy({ id: "x", cache: { paths: ["/a"], ttl_seconds: ttl } }).length,
        `ttl ${ttl}`,
      );
    }
  });

  it("rejects unsafe methods and non-object blocks", () => {
    assert.ok(
      validateCachePolicy({ id: "x", cache: { paths: ["/a"], ttl_seconds: 1, methods: ["POST"] } })
        .length,
    );
    assert.ok(
      validateCachePolicy({ id: "x", cache: { paths: ["/a"], ttl_seconds: 1, methods: [] } }).length,
    );
    assert.ok(validateCachePolicy({ id: "x", cache: "yes" }).length);
    assert.ok(validateCachePolicy({ id: "x", cache: [] }).length);
  });
});

describe("compileCachePolicy", () => {
  it("returns null without cache or when invalid", () => {
    assert.equal(compileCachePolicy({ id: "x" }), null);
    assert.equal(compileCachePolicy({ id: "x", cache: { paths: [] } }), null);
  });

  it("defaults methods to GET+HEAD", () => {
    const p = compileCachePolicy({ id: "x", cache: { paths: ["/a/"], ttl_seconds: 5 } });
    assert.deepEqual([...p.methods], ["GET", "HEAD"]);
    assert.equal(p.ttlSeconds, 5);
  });
});

describe("cacheEligible", () => {
  const policy = compileCachePolicy(filesCache);
  const url = "https://api.stawi.org/files/v1/public/media/srv/abc?width=10";

  it("matches GET/HEAD under a cache path with no Authorization", () => {
    assert.equal(cacheEligible(policy, new Request(url), "/v1/public/media/srv/abc"), true);
    assert.equal(
      cacheEligible(policy, new Request(url, { method: "HEAD" }), "/v1/public/media/srv/abc"),
      true,
    );
  });

  it("bypasses when Authorization is present", () => {
    const req = new Request(url, { headers: { Authorization: "Bearer t" } });
    assert.equal(cacheEligible(policy, req, "/v1/public/media/srv/abc"), false);
  });

  it("bypasses other paths and methods", () => {
    assert.equal(cacheEligible(policy, new Request(url), "/v1/media/srv/abc"), false);
    assert.equal(cacheEligible(policy, new Request(url), "/v1/public/mediax"), false);
    assert.equal(cacheEligible(policy, new Request(url, { method: "POST" }), "/v1/public/media/x"), false);
    assert.equal(cacheEligible(null, new Request(url), "/v1/public/media/x"), false);
  });
});

describe("cacheKey", () => {
  it("keeps the full URL including query and normalises HEAD to GET", () => {
    const url = "https://api.stawi.org/files/v1/public/media/s/m/thumbnail?width=64&height=64";
    const key = cacheKey(new Request(url, { method: "HEAD", headers: { "If-None-Match": '"e1"' } }));
    assert.equal(key.url, url);
    assert.equal(key.method, "GET");
    assert.equal(key.headers.get("If-None-Match"), '"e1"');
  });
});

describe("responseStorable", () => {
  const get = new Request("https://api.stawi.org/files/v1/public/media/s/m");
  const ok = (headers) => new Response("x", { status: 200, headers });
  const immutable = { "Cache-Control": "public, max-age=31536000, immutable", ETag: '"e1"' };

  it("stores public 200 to GET", () => {
    assert.equal(responseStorable(get, ok(immutable)), true);
  });

  it("does not store HEAD, non-200, partial, or not-modified", () => {
    assert.equal(responseStorable(new Request(get.url, { method: "HEAD" }), ok(immutable)), false);
    for (const status of [206, 304, 301, 404, 500]) {
      assert.equal(
        responseStorable(get, new Response(status === 304 ? null : "x", { status, headers: immutable })),
        false,
        `status ${status}`,
      );
    }
  });

  it("does not store cookies, private/no-store, missing public, or Vary *", () => {
    assert.equal(responseStorable(get, ok({ ...immutable, "Set-Cookie": "a=b" })), false);
    assert.equal(responseStorable(get, ok({ "Cache-Control": "private, max-age=60" })), false);
    assert.equal(responseStorable(get, ok({ "Cache-Control": "public, no-store" })), false);
    assert.equal(responseStorable(get, ok({ "Cache-Control": "max-age=60" })), false);
    assert.equal(responseStorable(get, ok({})), false);
    assert.equal(responseStorable(get, ok({ ...immutable, Vary: "*" })), false);
  });
});
