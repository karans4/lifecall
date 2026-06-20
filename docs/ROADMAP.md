# LifeCall — Product Roadmap

**Goal:** paid launch with real customers.
**Shape:** horizontal — a configurable voice cold-call → CRM pipeline for *any*
vertical (life insurance is the default playbook).

This ordering reflects that goal: things that block charging money come first.
Compliance is **not** deferred — a horizontal tool whose paying customers call
strangers puts TCPA/consent/recording liability on us as the platform.

---

## Where we are (done)
- Deployed Cloudflare Worker backend (D1 + KV + R2), Apple-verified sessions
- LLM brain: Kimi K2 via Groq (US), through the Worker
- Voice: ElevenLabs agent (custom-LLM → Worker); one live ~90s call verified
- Playbook engine (config-as-pipeline): script, collect fields + priority, urgency
  tiers + auto-actions, doc routing, calendar config
- Consented self-clone (built, untested — needs paid ElevenLabs tier)
- AGPL-3.0, sole copyright (dual-license/monetize preserved)

---

## P0 — Blockers to charging money

### Finish the core loop
- [ ] Fix loud/speakerphone audio (earpiece default or toggle)
- [ ] Confirm call quality subjectively (sound, smarts, latency)
- [ ] Resend key → follow-up email + PDF actually send
- [ ] Wire app → `/v1/leads/extract` (one server-side pipeline, drop client extract)
- [ ] Test voice cloning on a paid ElevenLabs tier; per-rep voice override

### Multi-tenant (today it's effectively single-user)
- [ ] Per-user agent or per-conversation voice/prompt override (no shared "Jordan")
- [ ] Org/team model: accounts, roles (rep/manager), managers see reps' pipelines
- [ ] Onboarding: sign up → author playbook → connect calendar → first call
- [ ] In-app Playbook editor (the product's authoring surface)

### Billing
- [ ] Stripe: subscription tiers + usage-based overage (call minutes)
- [ ] Hard cost caps per account (runaway protection on ElevenLabs/OpenRouter/Twilio)
- [ ] Per-call cost tracking → margin visibility

### Compliance & legal (gates the launch)
- [ ] TCPA: consent capture + audit trail, calling-hours windows, DNC scrubbing
- [ ] Per-state call-recording consent; AI disclosure (done) surfaced in record
- [ ] PII: retention policy, deletion (GDPR/CCPA), encryption at rest
- [ ] Terms of Service + Privacy Policy + acceptable-use (ban illegal calling)
- [ ] Close out `SECURITY_REVIEW.md` items; verify Worker migration killed the criticals

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
