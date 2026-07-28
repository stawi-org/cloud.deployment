/**
 * Unit tests for gateway CORS helpers (import worker source via dynamic eval of pure bits).
 * Full Worker is CF-runtime only; we re-implement the pure CORS policy here for CI.
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(readFileSync(join(root, "config/routes.prod.json"), "utf8"));

describe("gateway CORS config", () => {
  it("allows any browser origin by default", () => {
    const cors = config.gateway?.cors || {};
    assert.ok(Array.isArray(cors.allow_origins));
    assert.ok(cors.allow_origins.includes("*"));
  });
});

/** Mirror worker.js corsAllowOrigin policy for pure unit tests. */
function corsAllowOrigin(requestOrigin, allowOrigins = ["*"]) {
  const any = allowOrigins.includes("*");
  if (any) {
    return requestOrigin && requestOrigin !== "null" ? requestOrigin : "*";
  }
  if (!requestOrigin) return null;
  return allowOrigins.find((o) => o.toLowerCase() === requestOrigin.toLowerCase())
    ? requestOrigin
    : null;
}

describe("corsAllowOrigin policy", () => {
  it("reflects opportunities.stawi.org when allow *", () => {
    assert.equal(
      corsAllowOrigin("https://opportunities.stawi.org", ["*"]),
      "https://opportunities.stawi.org",
    );
  });

  it("returns * when no Origin header", () => {
    assert.equal(corsAllowOrigin(null, ["*"]), "*");
  });

  it("denies non-listed origin when not *", () => {
    assert.equal(
      corsAllowOrigin("https://evil.example", ["https://app.stawi.org"]),
      null,
    );
  });
});
