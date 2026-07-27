#!/usr/bin/env node
/**
 * Smoke-test the live gateway (and optional direct origins).
 * Usage:
 *   node scripts/smoke-test.mjs
 *   GATEWAY_BASE=https://api.stawi.org node scripts/smoke-test.mjs
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(readFileSync(join(root, "config/routes.prod.json"), "utf8"));
const base = (process.env.GATEWAY_BASE || `https://${config.hostname}`).replace(/\/$/, "");

const failures = [];

async function check(name, url, expectOk) {
  try {
    const res = await fetch(url, {
      method: "GET",
      redirect: "manual",
      headers: { accept: "application/json,*/*" },
      signal: AbortSignal.timeout(20000),
    });
    const body = await res.text();
    const ok = expectOk(res, body);
    const mark = ok ? "OK " : "FAIL";
    console.log(`${mark} ${name} → ${res.status} ${url}`);
    if (!ok) failures.push({ name, url, status: res.status, body: body.slice(0, 200) });
  } catch (e) {
    console.log(`FAIL ${name} → ${e.message} ${url}`);
    failures.push({ name, url, error: String(e) });
  }
}

await check("gateway health", `${base}${config.gateway?.health_path || "/_gateway/health"}`, (r, b) => {
  if (r.status !== 200) return false;
  try {
    return JSON.parse(b).ok === true;
  } catch {
    return false;
  }
});

await check("docs hub HTML", `${base}/docs`, (r, b) => {
  return r.status === 200 && (b.includes("Scalar") || b.includes("createApiReference") || b.includes("@scalar"));
});

await check("docs catalog JSON", `${base}/_gateway/docs`, (r, b) => {
  if (r.status !== 200) return false;
  try {
    const j = JSON.parse(b);
    return Array.isArray(j.sources) && j.sources.length >= 1;
  } catch {
    return false;
  }
});

// Profile OpenAPI through gateway (prefix strip + server rewrite)
await check("profile openapi via gateway", `${base}/profile/openapi.yaml`, (r, b) => {
  if (r.status !== 200) return false;
  return b.includes("openapi") || b.includes("paths:") || b.includes('"paths"');
});

// Public routes: any status except gateway 502/521/connection is progress.
// App 404 means proxy + Cloud Run IAM path works.
for (const r of config.routes || []) {
  if (r.enabled === false) continue;
  if (r.public === false) {
    // Authenticated backends may return 401/403 — still means proxy worked.
    await check(
      `route ${r.id} (auth)`,
      `${base}${r.prefix}/`,
      (res) => res.status !== 502 && res.status !== 521 && res.status !== 0,
    );
    continue;
  }
  await check(
    `route ${r.id}`,
    `${base}${r.prefix}/`,
    (res) => res.status !== 502 && res.status !== 521 && res.status < 500,
  );
}

// Unknown path must 404 from gateway
await check("unknown path", `${base}/__no_such_service__/x`, (r, b) => {
  if (r.status !== 404) return false;
  try {
    return JSON.parse(b).error === "no_route";
  } catch {
    return false;
  }
});

if (failures.length) {
  console.error("\nSmoke failures:", failures.length);
  process.exit(1);
}
console.log("\nAll smoke checks passed.");
