# `opportunities-crawler`

Owns the **crawl Neon** project (separate from product/matching Neon).  
Long-running crawl pods still run on the Kubernetes `product-opportunities` namespace; this Cloud Run app exists primarily for:

1. Neon project + extensions
2. Secret Manager URLs (`opportunities-crawler-database-url`)
3. One-shot migrate Job (`DO_DATABASE_MIGRATE`)

| | |
|--|--|
| Image | `opportunities-crawler` |
| Neon | **Owns crawl DB** (not shared with matching) |
| Public path | none (private service, min instances 0) |
| Product DB | matching owns `opportunities-matching-database-url` |

Cluster env:

```text
DATABASE_URL         ← crawl Neon (this app)
PRODUCT_DATABASE_URL ← product Neon (matching)   # worker only
```
