# LifeCall Worker

The Cloudflare Worker backend. Holds every API key server-side, verifies Sign in
with Apple, owns the leads database, serves private PDFs, proxies the LLM, and sends
email. This replaces Insforge and resolves the client-side-key vulnerabilities.

## Status (deployed)

- **Live:** `https://lifecall.karans4.workers.dev`
- **Provisioned:** D1 `lifecall` (leads + playbooks), KV `USAGE` (metering),
  R2 `lifecall-documents` (private PDFs). Schema applied.
- **Secrets set:** `SESSION_SECRET` ✅
- **Secrets still needed** (routes return 503 until set):
  `OPENROUTER_API_KEY` (LLM + extraction), `CUSTOM_LLM_TOKEN` (ElevenLabs → LLM proxy),
  `ELEVENLABS_API_KEY` (+ create the agent, set `elevenLabsAgentId` in the app),
  `RESEND_API_KEY` (email). `TWILIO_*` for outbound phone (phase 2).

## Routes

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/v1/auth` | Apple identity token | Verify SIWA, mint a 30-day session |
| POST | `/v1/chat/completions` | session **or** `CUSTOM_LLM_TOKEN` | OpenRouter proxy (the endpoint ElevenLabs' agent calls) |
| GET | `/v1/leads` | session | List the signed-in agent's leads |
| POST | `/v1/leads` | session | Upsert a lead (owner-scoped) |
| POST | `/v1/documents` | session | Upload a PDF to private R2 |
| GET | `/v1/documents/:id` | session | Serve a PDF, owner-only |
| POST | `/v1/email` | session | Send via Resend |
| POST | `/v1/dial` | session | Consent-gated outbound (call placement = phase 2) |

## Provision (one-time)

```sh
cd worker
npm install
npx wrangler login

# D1
npx wrangler d1 create lifecall            # paste database_id into wrangler.toml
npm run db:init                            # apply schema.sql

# KV
npx wrangler kv namespace create USAGE     # paste id into wrangler.toml

# R2
npx wrangler r2 bucket create lifecall-documents

# Secrets
npx wrangler secret put OPENROUTER_API_KEY
npx wrangler secret put SESSION_SECRET     # `openssl rand -base64 32`
npx wrangler secret put RESEND_API_KEY
npx wrangler secret put CUSTOM_LLM_TOKEN   # shared secret ElevenLabs sends as Bearer
npx wrangler secret put ELEVENLABS_API_KEY # phase 2
npx wrangler secret put TWILIO_ACCOUNT_SID # phase 2
npx wrangler secret put TWILIO_AUTH_TOKEN  # phase 2

npm run deploy
```

## Notes

- Secrets never leave Cloudflare's vault. The iOS app holds **no** provider keys —
  only its session token.
- Leads are scoped by Apple user id (`owner`); a session can only read/write its own.
- PDFs live in a **private** bucket; the only way to read one is `/v1/documents/:id`
  with the owner's session — no public/guessable URLs.
- `/v1/dial` refuses any number without a row in `consents` (TCPA).
