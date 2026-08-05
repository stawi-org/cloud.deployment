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

- **opportunities-matching** — first consumer (`CHAT_AGENT_SERVICE_URI`)
  with contexts:
  - `stawi.placement.intake` — onboarding / dashboard refine
  - `stawi.opportunity.view` — side chat on an opportunity detail page

## Inference (sticky multi-key LLM)

Chat agent uses **sticky primary-with-failover** (not round-robin):

1. Prefer the highest-priority healthy API key for the primary model.
2. On degradable errors (429/5xx/401/403/timeouts), mark that key degraded for
   `INFERENCE_FAILOVER_COOLDOWN` and try the next key **in the same request**.
3. After cooldown, prefer the primary key again.
4. Optional secondary provider (OpenAI) only after the primary key pool is exhausted.

### Cloud Run env (tofu)

| Env | Value |
|-----|--------|
| `INFERENCE_PROVIDER` | `google` |
| `INFERENCE_MODEL` | `gemini-2.0-flash` |
| `INFERENCE_API_KEYS` | Secret Manager → ordered Google AI keys |
| `INFERENCE_SECONDARY_PROVIDER` | `openai` (active only when secondary keys are mapped) |
| `INFERENCE_SECONDARY_MODEL` | `gpt-4o-mini` |
| `INFERENCE_FAILOVER_COOLDOWN` | `2m` |
| `NOTIFICATION_SERVICE_URI` | `https://api.stawi.org/notification` |

Provider defaults (in app code):

| Provider | Base | Path |
|----------|------|------|
| `google` | `https://generativelanguage.googleapis.com/v1beta/openai` | `/chat/completions` |
| `openai` | `https://api.openai.com` | `/v1/chat/completions` |

### Seed secrets (required before/with apply)

```bash
# Primary Google AI Studio / Gemini API keys (comma-separated, priority order)
./scripts/seed-gcp-secrets.sh --project stawi-platform \
  --set platform-chat-agent-inference-api-keys="AIza…primary,AIza…backup"

# Optional OpenAI pool (after enabling secret_env_extra map in main.tf)
./scripts/seed-gcp-secrets.sh --project stawi-platform \
  --set platform-chat-agent-inference-secondary-api-keys="sk-…primary,sk-…backup"
```

Or:

```bash
printf '%s' 'AIza…primary,AIza…backup' | gcloud secrets versions add \
  platform-chat-agent-inference-api-keys \
  --project=stawi-platform --data-file=-
```

Tofu creates the secret **shells** (`extra_secret_ids`). A Cloud Run revision
that mounts `INFERENCE_API_KEYS` will not start until the primary secret has
at least one version.

### Enable OpenAI secondary

1. Seed `platform-chat-agent-inference-secondary-api-keys`.
2. Uncomment `INFERENCE_SECONDARY_API_KEYS` in `cloudrun/main.tf` `secret_env_extra`.
3. Re-apply: `gh workflow run app-apply.yml -f app=platform-chat-agent -f env=stawi-prod`

Until secondary keys are mapped, the app runs **Google multi-key only**
(secondary provider env is ignored when keys are absent).

## Omnichannel

ChatAgent is **channel-agnostic**: sessions may bind a Notification target
(SMS / WhatsApp / email / push / in-app). Assistant replies call
`NotificationService.Send`. Web sessions omit the target and use RPC only.

## Ship

```text
service-profile tag vX.Y.Z
  → docker-release builds ghcr.io/antinvestor/service-profile-chatagent:vX.Y.Z
  → cloudrun-ship job ship-platform-chat-agent
```

OpenTofu apply (env / secrets / first deploy):

```bash
gh workflow run app-apply.yml -f app=platform-chat-agent -f env=stawi-prod
```

Image pins: `cloudrun/envs/stawi-prod.tfvars` (bootstrap). Routine rolls use
`cloudrun-ship` and ignore image drift in OpenTofu after first apply.
