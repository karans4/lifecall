# LifeCall — HN launch kit

> Framing: open-source voice-agent pipeline. Self-host free with your own keys;
> optional hosted tier priced only to cover API/voice/LLM credits. AI is disclosed.

---

## Show HN title (pick one)

1. **Show HN: LifeCall – open-source voice AI agent pipeline (Vapi + Nebius + Insforge)**
2. **Show HN: A full voice AI sales-agent pipeline I built in a day, open source**
3. **Show HN: Open-source voice agent that calls, qualifies, and writes a follow-up PDF**

Recommended: **#1** (clear, names the stack, signals open source).

---

## Post body

LifeCall is an open-source voice AI agent that runs a complete phone conversation
end to end: it talks to a person in real time, then turns the call into structured
data, a CRM record, a generated PDF, and a follow-up email — automatically.

I built it in a day for a hackathon and have been cleaning it up since. It's an iOS
app (SwiftUI) wired to three services:

- **Vapi** handles the voice layer — live in-app conversation (WebRTC) and real
  outbound phone calls, with interruption handling and smart turn-taking.
- **Nebius** (Llama-3.3-70B) is the brain. It's used three ways: as the live
  conversational agent, as a post-call extractor that pulls a structured lead out
  of the transcript, and to draft the follow-up email + pick which documents to send.
- **Insforge** is the backend — Postgres for the CRM, file storage for the generated
  PDF proposal, and transactional email.

The agent **introduces itself as an AI** at the start of every call — that was a
deliberate change from the hackathon version. The example use case is insurance
intake, but the pipeline is use-case agnostic; it's really "voice in → structured
outcome out."

It's **open source and free to self-host** with your own API keys. I'll also run a
hosted version, priced only to cover the underlying API/voice/LLM credits — I'm not
trying to mark it up, just not eat the bill.

Repo: https://github.com/karans4/lifecall
Demo video: <LINK>

Would love feedback on the architecture, the agent prompt design, or where this
breaks. Happy to answer anything.

---

## First comment (post this yourself right after, as OP)

A few honest notes since I know the questions are coming:

- **Consent / TCPA:** outbound calling people is legally regulated, and I take that
  seriously — the hosted version is built around opt-in / inbound and consented
  callbacks, not cold-dialing strangers. Self-hosters are responsible for their own
  compliance. The agent also discloses it's an AI up front.
- **Why it's interesting technically:** the hard part wasn't any single API, it was
  the seams — capturing the authoritative transcript after a call ends (not the racy
  live one), turning a messy spoken transcript into clean structured fields with an
  LLM, generating the PDF on-device and serving it via a public bucket, and making
  the whole post-call pipeline idempotent so a backgrounded app doesn't drop a lead.
- **Stack honesty:** Vapi orchestrates STT/turn-detection/TTS; Nebius is the LLM via
  Vapi's custom-llm hook and again server-side; Insforge is DB + storage + email. No
  servers of my own.
- It started as a life-insurance demo because I used to sell it and know the script.
  The pipeline doesn't care about the vertical.

Ask me anything — and tell me where it's wrong.

---

## Demo video script (~75 seconds, screen recording — NOT live PSTN)

0:00–0:08  — App opens. "This is LifeCall, an open-source voice agent. Tap to talk."
0:08–0:35  — Tap the orb. Short live conversation: agent says "Hey, I'm an AI
             assistant from LifeCall, mind if I ask a couple quick questions?" You
             answer a few (coverage, budget). Agent recommends a carrier, books a
             follow-up time. Keep it 25s, tight.
0:35–0:45  — Hang up. "The moment the call ends, the pipeline runs."
0:45–0:58  — A structured lead appears in the pipeline (name, coverage, premium,
             callback). Tap it → the dossier (summary + fact-find).
0:58–1:08  — Cut to the inbox: the follow-up email with the "View proposal" button.
             Click → the generated PDF.
1:08–1:15  — "Voice by Vapi, brain by Nebius, backend by Insforge. Open source,
             link below." End.

Tips: record in a quiet room, pre-stage the email, do 2–3 takes, no live phone
calls (mic + rate limits will betray you). A clean recording is the whole point.
