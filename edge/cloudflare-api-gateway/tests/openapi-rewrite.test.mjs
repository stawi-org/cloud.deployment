import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  isOpenAPIPath,
  rewriteOpenAPIServers,
} from "../src/openapi-rewrite.js";

describe("isOpenAPIPath", () => {
  it("matches common basenames", () => {
    assert.equal(isOpenAPIPath("/openapi.yaml"), true);
    assert.equal(isOpenAPIPath("/openapi.json"), true);
    assert.equal(isOpenAPIPath("/foo/swagger.json"), true);
  });

  it("matches frame multi-spec index", () => {
    assert.equal(isOpenAPIPath("/debug/frame/openapi"), true);
    assert.equal(isOpenAPIPath("/debug/frame/openapi/profile"), true);
  });

  it("rejects normal API paths", () => {
    assert.equal(isOpenAPIPath("/profile.v1.ProfileService/Get"), false);
    assert.equal(isOpenAPIPath("/"), false);
  });
});

describe("rewriteOpenAPIServers", () => {
  it("rewrites JSON servers", () => {
    const raw = JSON.stringify({
      openapi: "3.1.0",
      info: { title: "T", version: "1" },
      paths: {},
      servers: [{ url: "https://old.example" }],
    });
    const out = rewriteOpenAPIServers(raw, "application/json", "https://api.stawi.org/profile");
    const doc = JSON.parse(out.body);
    assert.equal(doc.servers[0].url, "https://api.stawi.org/profile");
    assert.match(out.contentType, /json/);
  });

  it("injects YAML servers when missing", () => {
    const raw = "openapi: 3.1.0\ninfo:\n  title: T\npaths: {}\n";
    const out = rewriteOpenAPIServers(raw, "application/yaml", "https://api.stawi.org/files");
    assert.match(out.body, /servers:\n  - url: https:\/\/api\.stawi\.org\/files/);
    assert.match(out.body, /openapi: 3\.1\.0/);
  });

  it("replaces existing YAML servers block", () => {
    const raw =
      "openapi: 3.1.0\nservers:\n  - url: https://old\npaths: {}\n";
    const out = rewriteOpenAPIServers(raw, null, "https://api.stawi.org/profile");
    assert.match(out.body, /api\.stawi\.org\/profile/);
    assert.equal(out.body.includes("https://old"), false);
  });
});
