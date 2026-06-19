# LifeCall

A voice-first AI life-insurance agent for iOS. Built for a multimodal AI agent
hackathon (sponsors: **Vapi**, **Nebius**, **Insforge**).

"Jordan," an AI closer, runs a real telesales qualification call — in-app live
voice or a real outbound phone call — then the pipeline runs itself: it extracts
a structured lead, saves it to a CRM, generates a personalized coverage proposal
PDF, and emails it.

## The flow

1. **Talk to Jordan** — tap the orb for live voice, or dial a real number. He runs
   a genuine producer's script: rapport → motive → fact-find (DIME) → health
   knockouts → budget → recommend a real carrier/product → close, handling
   objections along the way, and books a follow-up time.
2. **Call ends → it captures itself.** Nebius reads the transcript and extracts a
   structured lead (name, age, coverage, premium, email, phone, callback time) plus
   a conversation summary and full fact-find.
3. **Lead saves to Insforge** and appears in the in-app pipeline + Schedule tab.
4. **Personalized PDF proposal** is generated on-device (PDFKit), uploaded to
   Insforge storage, and emailed with the situation-appropriate documents.

## Stack

- **Vapi** — voice (in-app WebRTC SDK + outbound PSTN), built on Daily.
- **Nebius** — the LLM (`meta-llama/Llama-3.3-70B-Instruct`) via Vapi `custom-llm`,
  and app-side for lead extraction + email composition.
- **Insforge** — Postgres `leads` table (REST), file storage, and transactional email.
- **SwiftUI** — iOS 17, project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Build

```sh
# 1. Provide your keys
cp Secrets.example.swift Sources/Secrets.swift   # then fill in your keys

# 2. Generate the Xcode project
xcodegen generate

# 3. Build to a connected device
xcodebuild -project LifeCall.xcodeproj -scheme LifeCall \
  -destination 'id=YOUR_DEVICE_ID' -allowProvisioningUpdates build
```

You'll also need an Insforge project with a `leads` table (see
`migrations/`) and a public `documents` storage bucket, plus a Vapi phone number
configured in `Config.swift`.

## Notes

- Real API keys live in `Sources/Secrets.swift`, which is gitignored. Never commit it.
- Outbound calls to a stranger's cell are often carrier spam-filtered; demo with a
  consenting number that's expecting the call, or use the in-app voice orb.
