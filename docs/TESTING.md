# LifeCall — validation checklist

Quick steps to verify the live system. Run these when you're back.

## 1. Voice stack decision (the blocker)
**Cloudflare-native prototype** — the chosen direction. Test client served locally:
- It's running at **http://localhost:8789** (if not: `python3 -m http.server 8789 --directory voice-agent/client` from repo root).
- Click **Start call**, allow mic, talk to Jordan.
- Judge: **latency** (should feel snappier than Vapi — all co-located) and **voice** (Aura-2; not onyx yet — TTS is swappable once you like the architecture).
- Decision: if latency/feel is good → we build the iOS Swift WS client + plug onyx/Cartesia TTS. If not → fall back to Vapi-onyx (works today, higher latency).

Compare against **Vapi onyx** (works, validated): assistant `a9fe3606…`, voice onyx, our Worker brain. Higher latency was the complaint.

## 2. Billing (Stripe test mode)
- In the iOS app: header chip → **Buy hours** → pick a pack → in-app webview Checkout.
- Use test card **4242 4242 4242 4242**, any future expiry, any CVC.
- Webview should **close itself** on success; chip flips to **"Adding hours…"** then shows the new balance (webhook credits within seconds).
- Pricing: $20→$12/hr volume packs. Apple takes 0% (web checkout).
- Idempotency verified server-side (no double-credit on redelivery).

## 3. Outbound call (Twilio TRIAL)
- Pre-req: verify your test number in **Twilio → Verified Caller IDs** (trial only calls verified numbers; upgrade to call real leads).
- In the app: type your number → **Call** → confirm the **consent attestation** alert → it records consent (`/v1/consent`) then dials.
- Gates in order: DNC → consent → balance(≥60s) → daily cap → dial.
- Note: phone-call duration isn't debited from hours yet (server-authoritative metering = TODO).

## 4. Backend health (already green)
All routes auth-gated + smoke-tested: `/v1/auth` 400, `/v1/leads` 401, `/v1/billing/packs` 200,
`/v1/dial` 401, `/v1/stripe/webhook` 400 (bad sig), `/v1/chat/completions` 200 (Kimi/Groq).

## Known TODOs (need your input/keys)
- **Resend key** → follow-up email + PDF (route ready, key unset).
- **Server-authoritative metering** (pending voice-stack choice).
- **In-app test calls should be free** (you said in-app = test-only; not yet wired).
- Multi-tenant, compliance docs (ToS/Privacy), calling-hours, flip Stripe to live.
