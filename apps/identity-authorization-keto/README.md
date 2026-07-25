# `identity-authorization-keto`

Ory Keto (read + write) for ReBAC. **Control plane — not public.**

| Field | Value |
|-------|--------|
| **gcp.account** | `identity` |
| **neon.account** | `identity` |
| **Exposure** | `authenticated` (default): no `allUsers`; IAM invoker required |
| **Edge host** | **None** (must not appear on `edge-lb-identity`) |

## Privacy

See [docs/SERVICE_EXPOSURE.md](../../docs/SERVICE_EXPOSURE.md).

- Default invokers: identity Frame runtime SAs + this service’s SA (keep-warm OIDC).
- Cross-project callers (ops/platform): set `additional_invoker_members` in tfvars.
- When Shared VPC is ready: `exposure = "private"`.

## Deploy

```bash
./.github/scripts/resolve-app-context.sh identity-authorization-keto stawi-prod
gh workflow run app-apply.yml -f app=identity-authorization-keto -f env=stawi-prod
```

Verify anonymous access is denied:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' "$KETO_READ_URI/health/ready"   # expect 403
```
