# Cross-platform & code reuse

Where LifeCall can run, what's reusable, and the dead ends — so we don't
re-litigate this later. Current client is SwiftUI (iOS); backend is a
platform-agnostic Cloudflare Worker.

## TL;DR

- **iOS** — current native client.
- **macOS** — high reuse; make it a multiplatform SwiftUI target. ~1–2 days.
- **Windows / Linux / browser** — **web is the only real answer.** Swift/SwiftUI
  does not run on Windows, and the SwiftUI-on-web path just died (Tokamak archived
  Jan 2026). Build a web console on the same Worker; keep Swift as the mobile/Mac tier.

## What's reusable, by layer

| Layer | macOS | Web (JS) | Notes |
|---|---|---|---|
| Cloudflare Worker (all backend) | ✅ 100% | ✅ 100% | Just HTTP; every client hits the same API |
| Models (`Lead`, `Playbook`) | ✅ | rewrite in TS | Codable → trivial TS mirror |
| `WorkerAPI` (URLSession) | ✅ | rewrite (fetch) | Same endpoints |
| `LeadExtractor` / `EmailComposer` logic | ✅ | rewrite | Logic ports conceptually |
| `AuthStore` (Sign in with Apple) | ✅ AuthenticationServices works on macOS | Sign in with Apple **JS** web flow | Worker verifies the same identity token |
| SwiftUI views | ✅ with `#if os()` guards | ❌ rebuild | iOS-only bits: `import UIKit`, keyboard dismiss, `.keyboardType`, some modifiers |
| `PDFGenerator` (UIKit) | ⚠️ port to CoreGraphics | server-side or JS | One-time port makes it cross-platform for iOS+macOS too |
| Voice (ElevenLabs SDK, LiveKit-based) | ✅ LiveKit supports macOS | ✅ ElevenLabs/LiveKit **JS SDKs** | Web SDKs are arguably easier than the Swift one |

## macOS path

Make it a **multiplatform SwiftUI app** (single target, iOS + macOS) in `project.yml` —
don't fork. Shared: `@main App`, models, `WorkerAPI`, `AuthStore`, most views.
Platform differences behind `#if os(macOS)`. Real work: port `PDFGenerator` from
UIKit → CoreGraphics, verify ElevenLabs/LiveKit macOS support + mic entitlements.
A desktop "agent console" (run calls, watch the pipeline, edit playbooks) is a
strong fit for Mac.

## Windows / web reality

- **Swift/SwiftUI does not run on Windows.** The Swift *language* has a Windows
  toolchain, but there is **no SwiftUI** (no Apple UI framework) on Windows. The UI
  layer — most of the reusable view code — does not carry over.
- For Windows/Linux/browser reach, the answer is a **web frontend** (React/Svelte)
  on the existing Worker. Reuses the backend 100%; rebuild the UI once.
  - Voice: ElevenLabs + LiveKit both ship first-class **JS/React SDKs**.
  - Auth: **Sign in with Apple JS** web flow; the Worker already verifies the token.
    Can add Google/email auth for non-Apple users.
  - Optional: **Tauri-wrap** the web app → installable Windows + Mac desktop from one
    codebase (we already use Tauri in diffs-ide).

## SwiftUI-on-web hacks (investigated — all dead ends for a real app)

- **Tokamak** — *was* the SwiftUI-compatible framework for the browser (reimplemented
  the SwiftUI API → DOM via SwiftWasm). **Archived Jan 2026, read-only, seeking
  maintainers.** Always lagged real SwiftUI (CSS-approximated layout, version lag).
  Don't build on it.
- **SwiftWasm + JavaScriptKit** — alive. Compiles Swift → WebAssembly and can touch
  the DOM. Lets you reuse *non-UI* Swift (models, API client, logic) in the browser,
  but you render the UI by hand via DOM/JS — **you still rewrite the views**, with
  large WASM bundles and a small community. Not worth it for a CRM.
- **Ignite** (Paul Hudson) — SwiftUI-*flavored* DSL, but generates **static HTML
  sites**, not interactive apps. Wrong tool.
- **Skip** (skip.tools) — transpiles SwiftUI → **Android/Compose**, not web.
- **swift-html / Elementary** — server-side HTML DSLs, not SwiftUI.

Key fact: **SwiftUI itself is closed-source and cannot target the web** — every
"SwiftUI on web" option is an API *reimplementation*, and the only serious one is now
archived. Reuse the logic via WASM at best; never the actual views.

## Recommendation

- **Apple-native** (iOS + macOS multiplatform SwiftUI) for the native tier.
- **Web console** (React/Svelte on the same Worker, + ElevenLabs JS, Sign in with
  Apple JS; optional Tauri shell) for Windows/Linux/browser.
- Do **not** invest in Swift-on-web; the path is a dead end as of 2026.

Sources: Tokamak archived (github.com/TokamakUI/Tokamak), SwiftWasm, Carson Katri
"Deploying SwiftUI on the Web".
