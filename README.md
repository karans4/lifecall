# LifeCall

An **open-source voice AI agent pipeline** for iOS: voice in → structured outcome out.
"Jordan" holds a real-time phone conversation — in-app (WebRTC) or a real outbound
call — and the moment it ends the pipeline runs itself: it extracts a structured
lead, saves it to a CRM, generates a personalized PDF, and sends a follow-up email.

The agent **introduces itself as an AI** on every call. The example vertical is
insurance intake (it ships with a real qualification script), but the pipeline is
use-case agnostic.

Built with **ElevenLabs** (voice agent), **OpenRouter** (LLM), and a **Cloudflare
Worker** backend (D1 + R2 + Resend). The iOS app holds **no provider keys** — it
authenticates with Sign in with Apple and talks only to the Worker, which holds
every secret server-side. Free tier runs fully on-device (iOS 26 FoundationModels).

- **Self-host:** deploy the Worker (`worker/`) with your own keys, point the app at it.
- **Hosted:** an optional managed version, priced only to cover the underlying
  voice / LLM credits — no markup.

> Calling people is regulated (e.g. TCPA in the US). Use outbound only with consent;
> the agent discloses it's an AI. You are responsible for compliance when self-hosting.

## The flow

1. **Talk to Jordan** — tap the orb for live voice, or dial a real number. He runs
   a genuine producer's script: rapport → motive → fact-find (DIME) → health
   knockouts → budget → recommend a real carrier/product → close, handling
   objections along the way, and books a follow-up time.
2. **Call ends → it captures itself.** Nebius reads the transcript and extracts a
   structured lead (name, age, coverage, premium, email, phone, callback time) plus
   a conversation summary and full fact-find.
3. **Lead saves to the Worker (Cloudflare D1)**, owner-scoped, and appears in the
   in-app pipeline + Schedule tab.
4. **Personalized PDF proposal** is generated on-device (PDFKit), uploaded to
   private R2 storage via the Worker, and emailed with the right documents.

## Stack

- **ElevenLabs** — Conversational AI agent: in-app voice SDK + Twilio phone, STT +
  premium TTS + turn-taking. Its LLM is the Worker's OpenRouter proxy.
- **OpenRouter** — the LLM, reached only through the Worker (no key on device).
- **Cloudflare Worker** (`worker/`) — the backend: Sign in with Apple verification,
  D1 (leads), R2 (private PDFs), Resend (email), the LLM proxy, consent-gated dialing.
- **iOS 26 on-device** — free tier: FoundationModels + SpeechAnalyzer + AVSpeech.
- **SwiftUI** — iOS 17+, project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Status

Backend is **live** at `https://lifecall.karans4.workers.dev` (D1 + KV + R2 +
Sign in with Apple sessions deployed). Remaining setup is provider API keys —
`OPENROUTER_API_KEY`, `ELEVENLABS_API_KEY` (+ agent), `RESEND_API_KEY`,
`CUSTOM_LLM_TOKEN` — see [worker/README.md](worker/README.md).

## Build

```sh
# 1. Backend is already deployed (see worker/README.md). The app's
#    Config.workerBaseURL points at it; set elevenLabsAgentId once the agent exists.

# 2. Generate the Xcode project
xcodegen generate

# 3. Build to a connected device
xcodebuild -project LifeCall.xcodeproj -scheme LifeCall \
  -destination 'id=YOUR_DEVICE_ID' -allowProvisioningUpdates build
```

## Notes

- The app holds **no** provider keys — only a Sign in with Apple session token. All
  secrets live in the Worker (Cloudflare secrets). See `worker/README.md`.
- Outbound phone calls are consent-gated server-side (TCPA). The agent discloses
  it's an AI on every call.

## License

Licensed under the **GNU Affero General Public License v3.0** — see [LICENSE](LICENSE).

AGPL's network clause matters here: if you run a modified version of LifeCall as a
hosted service, you must make your modified source available to its users.

© 2026 Karan Sharma
