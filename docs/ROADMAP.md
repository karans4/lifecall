# LifeCall — Product Roadmap

**Goal:** paid launch with real customers.
**Shape:** horizontal — a configurable voice cold-call → CRM pipeline for *any*
vertical (life insurance is the default playbook).

This ordering reflects that goal: things that block charging money come first.
Compliance is **not** deferred — a horizontal tool whose paying customers call
strangers puts TCPA/consent/recording liability on us as the platform.

---

## Where we are (done — as of 2026-06-20 PM)
- Deployed Cloudflare Worker backend (D1 + KV + R2), **Apple-verified sessions** (fixed
  a sub-truncation bug; users must re-sign-in once)
- LLM brain: Kimi K2 via Groq (US), through the Worker
- **Billing LIVE (Stripe test mode):** prepaid **call-hours**, volume pricing $20→$12/hr
  floor, per-second debit on call end, in-app webview Checkout, **webhook idempotent**
  (no double-credit), buy-hours UI. Apple takes 0% (B2B web billing).
- **Real outbound calling wired** (consent-gated, TCPA): `/v1/dial` + in-app consent
  attestation + E.164 normalization. Twilio number `+15108801709` imported.
- **Playbook engine** (config-as-pipeline): script, collect fields + priority, urgency
  tiers + auto-actions, doc routing, calendar config
- Consented self-clone (built, untested — needs paid ElevenLabs tier)
- AGPL-3.0, sole copyright (dual-license/monetize preserved)

### Voice stack — DECISION IN PROGRESS
- ElevenLabs hang-up root-caused + fixed (doubled custom-LLM URL path). Karan disliked
  ElevenLabs voices; wants OpenAI **onyx**.
- **Vapi onyx path works** (validated live) but latency too high.
- **CHOSEN: Cloudflare-native voice agent** (`withVoice`) — prototype DEPLOYED
  (`lifecall-voice.karans4.workers.dev`, `voice-agent/`): Kimi K2.6 on Workers AI +
  Workers AI STT/TTS, all co-located (~350–500ms). TTS swappable to onyx/Cartesia.
  Pending: Karan's mic-test of quality/latency, then iOS (Swift WS/WebRTC) client.
- Wolf-of-Wall-Street persona, with disclosure + no-fabrication + qualify-out guardrails.

---

## P0 — Blockers to charging money

### Finish the core loop
- [x] Fix loud/speakerphone audio (earpiece default + in-call speaker toggle)
- [ ] **Settle the voice stack** (Cloudflare prototype mic-test → confirm quality/latency)
- [ ] Resend key → follow-up email + PDF actually send (route ready, key not set)
- [ ] Wire app → `/v1/leads/extract` (server pipeline ready; PDF/email still on-device)
- [ ] **Server-authoritative metering** — debit call-seconds from true call duration,
      not the client (matters now that hours = money)
- [ ] Make **in-app test calls free** (Karan: in-app is test-only, shouldn't burn hours)
- [ ] Test voice cloning on a paid ElevenLabs tier; per-rep voice override

### Multi-tenant (today it's effectively single-user)
- [ ] Per-user agent or per-conversation voice/prompt override (no shared "Jordan")
- [ ] Org/team model: accounts, roles (rep/manager), managers see reps' pipelines
- [ ] Onboarding: sign up → author playbook → connect calendar → first call
- [ ] In-app Playbook editor (the product's authoring surface)

### Billing
- [x] Stripe Checkout + webhook (prepaid call-hours, volume pricing) — **idempotent**
- [x] In-app webview Checkout (closes on success) + buy-hours UI + balance polling
- [ ] Hard cost caps per account (runaway protection on Twilio/voice/LLM)
- [ ] Per-call cost tracking → margin visibility; flip Stripe to live keys
- [ ] Dev/prod build configs before going live (separate worker + Stripe test/live)

### Compliance & legal (gates the launch)
- [~] TCPA consent: capture route + in-app attestation + audit trail done; still need
      calling-hours windows + DNC scrubbing
- [ ] Per-state call-recording consent; AI disclosure (done) surfaced in record
- [ ] PII: retention policy, deletion (GDPR/CCPA), encryption at rest
- [ ] Terms of Service + Privacy Policy + acceptable-use (ban illegal calling)
- [x] Worker migration killed the client-side-key criticals (keys server-side, owner-
      scoped data, private R2) — `SECURITY_REVIEW.md`. Remaining: metering trust, caps.

---

## P1 — Table stakes right after launch

### Product surface
- [ ] Calendar: Google OAuth + .ics invites
- [ ] DOCX generation + real document templates per playbook
- [ ] Auto-action execution (Hot → send docs / auto-book / auto-dial), gated
- [ ] CRM depth: search/filter, notes, pipeline stages, dedupe, CSV export
- [ ] Outbound phone (Twilio) with consent enforcement

### Reliability & ops
- [ ] Stop swallowing errors; structured logging + alerting (Sentry/PostHog)
- [ ] Worker tests + CI; rate limiting + abuse protection on public routes
- [ ] Health/status monitoring; on-call basics

### Go-to-market
- [ ] Landing page + pitch ("200 dials → 1 sale")
- [ ] Web console (Windows/cross-platform answer — see PLATFORMS.md)
- [ ] Pricing page, demo video, first design partners
- [ ] App Store submission (calling + AI disclosure will get scrutiny)

---

## P2 — Scale & moat
- [ ] Playbook marketplace / templates per vertical (lean into horizontal)
- [ ] Analytics: conversion funnels, per-rep performance, call scoring
- [ ] CRM integrations (Salesforce/HubSpot import-export)
- [ ] Inbound calls + warm-transfer to a human
- [ ] Cartesia voice swap (cost), prompt caching, latency tuning
- [ ] SOC 2 / security posture for enterprise deals
- [ ] macOS app (multiplatform SwiftUI)

---

## Biggest risks
1. **Compliance liability** — horizontal cold-calling platform; TCPA class actions
   are real. Likely need counsel before paid launch + strict acceptable-use + DNC.
2. **Unit economics** — voice (~$0.50/call) dominates; pricing must cover it with
   margin. Cartesia swap + caps matter.
3. **Voice-clone misuse** — consent gating + ToS; never clone non-consenting voices.
4. **Platform dependence** — ElevenLabs/OpenRouter/Groq pricing & availability.
