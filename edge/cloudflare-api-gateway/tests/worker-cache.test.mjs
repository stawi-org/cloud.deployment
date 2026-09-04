/**
 * End-to-end edge cache flow through the real Worker (src/worker.js) with
 * globalThis.fetch and globalThis.caches mocked. Uses the prod files route:
 * https://api.stawi.org/files/v1/public/media/... → origin /v1/public/media/...
 */
import { afterEach, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/worker.js";

const MEDIA = "https://api.stawi.org/files/v1/public/media/stawi.org/m1";
const THUMB = `${MEDIA}/thumbnail?width=64&height=64`;
const IMMUTABLE = "public, max-age=31536000, immutable";

/** Map-backed stand-in for caches.default (keyed by URL). */
function memoryCache() {
  const store = new Map();
  return {
    store,
    async match(req) {
      const e = store.get(req.url);
      if (!e) return undefined;
      return new Response(e.body, { status: e.status, headers: e.headers });
    },
    async put(req, res) {
      store.set(req.url, {
        status: res.status,
        headers: new Headers(res.headers),
        body: await res.arrayBuffer(),
      });
    },
  };
}

function ctx() {
  const pending = [];
  return {
    waitUntil: (p) => pending.push(p),
    settle: () => Promise.all(pending),
  };
}

function originStub(respond) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    return respond(String(url), init);
  };
  return calls;
}

const okMedia = (extra = {}) =>
  new Response("image-bytes", {
    status: 200,
    headers: { "Content-Type": "image/webp", "Cache-Control": IMMUTABLE, ETag: '"e1"', ...extra },
  });

let realFetch;
let cache;

beforeEach(() => {
  realFetch = globalThis.fetch;
  cache = memoryCache();
  globalThis.caches = { default: cache };
});

afterEach(() => {
  globalThis.fetch = realFetch;
  delete globalThis.caches;
});

describe("edge cache: files public media", () => {
  it("MISS stores the response, then HIT serves it without touching origin", async () => {
    const calls = originStub(() => okMedia());
    const c1 = ctx();
    const miss = await worker.fetch(new Request(MEDIA), {}, c1);
    await c1.settle();

    assert.equal(miss.status, 200);
    assert.equal(miss.headers.get("X-Gateway-Cache"), "MISS");
    assert.equal(miss.headers.get("ETag"), '"e1"');
    assert.equal(miss.headers.get("Cache-Control"), IMMUTABLE);
    assert.equal(await miss.text(), "image-bytes");
    assert.equal(calls.length, 1);
    assert.equal(
      calls[0].url,
      "https://platform-files-diujdvkz4a-ew.a.run.app/v1/public/media/stawi.org/m1",
    );
    assert.deepEqual(calls[0].init.cf, { cacheEverything: true, cacheTtl: 31536000 });
    assert.ok(cache.store.has(MEDIA), "stored under the public URL");

    const c2 = ctx();
    const hit = await worker.fetch(new Request(MEDIA), {}, c2);
    assert.equal(hit.status, 200);
    assert.equal(hit.headers.get("X-Gateway-Cache"), "HIT");
    assert.equal(hit.headers.get("x-stawi-route"), "files");
    assert.equal(hit.headers.get("ETag"), '"e1"');
    assert.equal(await hit.text(), "image-bytes");
    assert.equal(calls.length, 1, "origin not called on hit");
  });

  it("keys on the full URL including thumbnail query", async () => {
    const calls = originStub((url) => okMedia({ "X-Origin-Url": url }));
    const c = ctx();
    await worker.fetch(new Request(MEDIA), {}, c);
    const thumb = await worker.fetch(new Request(THUMB), {}, c);
    await c.settle();
    assert.equal(thumb.headers.get("X-Gateway-Cache"), "MISS");
    assert.equal(calls.length, 2);
    assert.ok(calls[1].url.endsWith("/thumbnail?width=64&height=64"));
    assert.ok(cache.store.has(MEDIA));
    assert.ok(cache.store.has(THUMB));
  });

  it("HEAD hits share the GET entry and return no body", async () => {
    const calls = originStub(() => okMedia());
    const c = ctx();
    await worker.fetch(new Request(MEDIA), {}, c);
    await c.settle();
    const head = await worker.fetch(new Request(MEDIA, { method: "HEAD" }), {}, c);
    assert.equal(head.headers.get("X-Gateway-Cache"), "HIT");
    assert.equal(head.body, null);
    assert.equal(calls.length, 1);
  });

  it("Authorization header bypasses the cache on both read and write", async () => {
    const calls = originStub(() => okMedia());
    const authed = () => new Request(MEDIA, { headers: { Authorization: "Bearer tok" } });
    const c = ctx();
    const r1 = await worker.fetch(authed(), {}, c);
    await c.settle();
    assert.equal(r1.headers.get("X-Gateway-Cache"), "BYPASS");
    assert.equal(cache.store.size, 0, "authorized response must not be stored");
    assert.equal(calls[0].init.cf, undefined);
    assert.equal(calls[0].init.headers.get("Authorization"), "Bearer tok");

    await worker.fetch(new Request(MEDIA), {}, c);
    await c.settle();
    assert.equal(cache.store.size, 1);
    const r3 = await worker.fetch(authed(), {}, c);
    assert.equal(r3.headers.get("X-Gateway-Cache"), "BYPASS");
    assert.equal(calls.length, 3, "authorized request goes to origin even when cached");
  });

  it("does not store non-2xx responses", async () => {
    let status = 404;
    originStub(() => new Response("nope", { status, headers: { "Cache-Control": IMMUTABLE } }));
    const c = ctx();
    const r = await worker.fetch(new Request(MEDIA), {}, c);
    await c.settle();
    assert.equal(r.status, 404);
    assert.equal(r.headers.get("X-Gateway-Cache"), "MISS");
    assert.equal(cache.store.size, 0);

    status = 500;
    await worker.fetch(new Request(MEDIA), {}, c);
    await c.settle();
    assert.equal(cache.store.size, 0);
  });

  it("does not store Set-Cookie, non-public, or 206 partial responses", async () => {
    const variants = [
      okMedia({ "Set-Cookie": "sid=1" }),
      new Response("x", { status: 200, headers: { "Cache-Control": "private, max-age=60" } }),
      new Response("x", { status: 200 }),
      new Response("part", {
        status: 206,
        headers: { "Cache-Control": IMMUTABLE, "Content-Range": "bytes 0-3/11" },
      }),
    ];
    for (const v of variants) {
      originStub(() => v);
      const c = ctx();
      const r = await worker.fetch(new Request(MEDIA, { headers: { Range: "bytes=0-3" } }), {}, c);
      await c.settle();
      assert.equal(r.status, v.status);
      assert.equal(cache.store.size, 0, `must not store ${v.status} ${[...v.headers.keys()]}`);
    }
  });

  it("passes If-None-Match to origin and returns its 304 uncached", async () => {
    const calls = originStub((url, init) =>
      init.headers.get("If-None-Match") === '"e1"'
        ? new Response(null, { status: 304, headers: { ETag: '"e1"', "Cache-Control": IMMUTABLE } })
        : okMedia(),
    );
    const c = ctx();
    const r = await worker.fetch(
      new Request(MEDIA, { headers: { "If-None-Match": '"e1"' } }),
      {},
      c,
    );
    await c.settle();
    assert.equal(r.status, 304);
    assert.equal(r.headers.get("ETag"), '"e1"');
    assert.equal(calls[0].init.headers.get("If-None-Match"), '"e1"');
    assert.equal(cache.store.size, 0);
  });

  it("leaves non-cache paths on the same route alone", async () => {
    const calls = originStub(() => okMedia());
    const c = ctx();
    const r = await worker.fetch(new Request("https://api.stawi.org/files/v1/media/private/m1"), {}, c);
    await c.settle();
    assert.equal(r.headers.get("X-Gateway-Cache"), "BYPASS");
    assert.equal(calls[0].init.cf, undefined);
    assert.equal(cache.store.size, 0);
  });

  it("works without caches.default (plain pass-through)", async () => {
    delete globalThis.caches;
    const calls = originStub(() => okMedia());
    const r = await worker.fetch(new Request(MEDIA), {}, ctx());
    assert.equal(r.status, 200);
    assert.equal(r.headers.get("X-Gateway-Cache"), "MISS");
    assert.equal(calls.length, 1);
  });
});
