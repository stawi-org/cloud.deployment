/**
 * Rewrite OpenAPI document servers to the gateway path base.
 * Pure helpers — unit-tested; used by the Worker after proxying specs.
 */

/**
 * @param {string} bodyText
 * @param {string|null} contentType
 * @param {string} serverUrl
 * @returns {{ body: string, contentType: string }}
 */
export function rewriteOpenAPIServers(bodyText, contentType, serverUrl) {
  const ct = (contentType || "").toLowerCase();
  const looksJson =
    ct.includes("json") ||
    bodyText.trimStart().startsWith("{") ||
    bodyText.trimStart().startsWith("[");

  if (looksJson) {
    try {
      const doc = JSON.parse(bodyText);
      if (doc && typeof doc === "object" && !Array.isArray(doc)) {
        doc.servers = [{ url: serverUrl, description: "Stawi API gateway" }];
        return {
          body: JSON.stringify(doc),
          contentType: "application/json; charset=utf-8",
        };
      }
    } catch {
      /* fall through to YAML */
    }
  }

  let yaml = bodyText;
  yaml = yaml.replace(/^servers:\n(?:[ \t]+.+\n)*/m, "");
  const inject = `servers:\n  - url: ${serverUrl}\n    description: Stawi API gateway\n`;
  if (/^openapi:\s*/m.test(yaml)) {
    yaml = yaml.replace(/^(openapi:\s*.+\n)/m, `$1${inject}`);
  } else {
    yaml = inject + yaml;
  }
  return {
    body: yaml,
    contentType: contentType || "application/yaml; charset=utf-8",
  };
}

/**
 * @param {string} strippedPath
 * @param {Set<string>} basenames
 */
export function isOpenAPIPath(
  strippedPath,
  basenames = new Set([
    "openapi.yaml",
    "openapi.yml",
    "openapi.json",
    "swagger.json",
    "swagger.yaml",
  ]),
) {
  const base = strippedPath.split("?")[0].split("/").filter(Boolean).pop() || "";
  if (basenames.has(base.toLowerCase())) return true;
  if (
    strippedPath === "/debug/frame/openapi" ||
    strippedPath.startsWith("/debug/frame/openapi/")
  ) {
    return true;
  }
  return false;
}
