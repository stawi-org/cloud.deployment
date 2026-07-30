# platform-chat-agent

Product-agnostic conversational **data-collection** service (Frame app from
`service-profile/apps/chatagent`).

| Layer | Value |
|-------|--------|
| GCP | `platform` / `stawi-platform` |
| Neon | `platform` org |
| Image | `ghcr.io/antinvestor/service-profile-chatagent` |
| Edge path | `https://api.stawi.org/chat-agent` |
| Audience | `/chat-agent` (`servicecatalog.ServiceChatAgent`) |
| Auth | Identity Hydra/Keto in `stawi-identity` |

## Consumers

- **opportunities-matching** — first consumer (`POST /matching/me/chat` adapter)
  with contexts:
  - `stawi.placement.intake` — onboarding / dashboard refine
  - `stawi.opportunity.view` — side chat on an opportunity detail page

## Env (app-only)

| Env | Purpose |
|-----|---------|
| `INFERENCE_BASE_URL` | OpenAI-compatible LLM root (optional) |
| `INFERENCE_API_KEY` | Bearer for inference |
| `INFERENCE_MODEL` | Default instruct model |

Ship via service-profile release tag → `cloudrun-ship` job `ship-platform-chat-agent`.
