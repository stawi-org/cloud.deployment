# Cloudflare API token for the API gateway Worker

The OpenTofu `edge-lb-*` apps only need **Zone → DNS → Edit**.

Deploying `stawi-api-gateway` needs a **broader** token (or a second secret).

## Required permissions

Account `c358ea38bde6fd03d13bf87068635230` (Ant Investor Account), zone `stawi.org`:

| Scope | Permission |
|-------|------------|
| Account | **Cloudflare Workers Scripts → Edit** |
| Account | **Account Settings → Read** (optional; quieter wrangler) |
| Zone | **Workers Routes → Edit** |
| Zone | **DNS → Edit** (keep for edge-lb OpenTofu) |
| Zone | **DNS → Read** |

## Create / update

1. https://dash.cloudflare.com/profile/api-tokens → **Create Token**
2. Use template **Edit Cloudflare Workers**, then add **Zone.DNS Edit** for `stawi.org`
   - Or Custom token with the table above
3. Resources: include account **Ant Investor Account** and zone **stawi.org**
4. Set GitHub secret (replaces DNS-only token if you use one token for both):

```bash
gh secret set CLOUDFLARE_API_TOKEN --repo stawi-org/cloud.deployment --body "$TOKEN"
# optional explicit account
gh secret set CLOUDFLARE_ACCOUNT_ID --repo stawi-org/cloud.deployment --body "c358ea38bde6fd03d13bf87068635230"
```

5. Redeploy:

```bash
gh workflow run edge-api-gateway.yml --repo stawi-org/cloud.deployment
```

## Verify token locally

```bash
export CLOUDFLARE_API_TOKEN=…
curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  https://api.cloudflare.com/client/v4/accounts/c358ea38bde6fd03d13bf87068635230/workers/scripts \
  | head -c 400; echo
# success → result array; 10000 → still missing Workers Edit
```
