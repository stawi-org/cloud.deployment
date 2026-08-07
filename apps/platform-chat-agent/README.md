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
| `INFERENCE_MODEL` | `gemini-3.6-flash` |
| `INFERENCE_API_KEYS` | Secret Manager → ordered Google AI keys |
| `INFERENCE_SECONDARY_PROVIDER` | `custom` (NVIDIA Build OpenAI-compat) |
| `INFERENCE_SECONDARY_BASE_URL` | `https://integrate.api.nvidia.com` |
| `INFERENCE_SECONDARY_MODEL` | `meta/llama-3.1-8b-instruct` |
| `INFERENCE_SECONDARY_API_KEYS` | Secret Manager NVIDIA `nvapi-…` key(s) |
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

# Secondary: NVIDIA Build API key (OpenAI-compat at integrate.api.nvidia.com)
./scripts/seed-gcp-secrets.sh --project stawi-platform \
  --set platform-chat-agent-inference-secondary-api-keys="nvapi-…"
```

Or:

```bash
printf '%s' 'AIza…primary,AIza…backup' | gcloud secrets versions add \
  platform-chat-agent-inference-api-keys \
  --project=stawi-platform --data-file=-

printf '%s' 'nvapi-…' | gcloud secrets versions add \
  platform-chat-agent-inference-secondary-api-keys \
  --project=stawi-platform --data-file=-
```

Tofu creates the secret **shells** (`extra_secret_ids`). A Cloud Run revision
that mounts these secrets will not start until each mapped secret has at least
one version.

### Failover chain

1. Google `gemini-3.6-flash` keys (`INFERENCE_API_KEYS`) — sticky primary  
2. NVIDIA `meta/llama-3.1-8b-instruct` via `https://integrate.api.nvidia.com` — after primary degrades

### Troubleshooting: both providers fail with auth errors

If logs look like:

```text
primary [google] … status=400: Please pass a valid API key
secondary [custom] … status=401: Authentication failed
```

but the same Secret Manager keys return **HTTP 200** when probed from a laptop
against Gemini/NVIDIA, the keys are fine — the LLM HTTP client was almost
certainly attaching the service’s **OAuth bearer** and overwriting
`Authorization: Bearer <api-key>`.

**Fix (service-profile chatagent):** build the inference client with
`frameclient.WithHTTPNoAuth()` (same pattern as opportunities matching /
crawler for external inference). Requires a chat-agent image that includes
that change (post `v1.54.12`).

Also confirm secrets are AI Studio `AIza…` / NVIDIA `nvapi-…` with no
application (IP/HTTP-referrer) restrictions that block Cloud Run egress.

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
