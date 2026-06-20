// LifeCall voice agent on Cloudflare's native stack — STT, LLM, TTS, and media all
// co-located in one datacenter (350–500ms voice-to-voice). Cuts Vapi entirely:
// Kimi runs on Workers AI, STT/TTS on Workers AI (Flux + Aura), transport via
// Cloudflare Realtime. Swap the TTS for OpenAI onyx / Cartesia when chosen.
import { Agent, routeAgentRequest, type Connection } from "agents";
import { withVoice, WorkersAIFluxSTT, WorkersAITTS, type VoiceTurnContext } from "@cloudflare/voice";
import { streamText } from "ai";
import { createWorkersAI } from "workers-ai-provider";

// Jordan — deep Wolf-of-Wall-Street closer, with AI-disclosure + honesty guardrails.
const SYSTEM_PROMPT = `You are Jordan, an AI assistant for a licensed life-insurance brokerage on a phone call.
DISCLOSE you're an AI in your opener; never pretend to be human. Never invent prior contact, callbacks, or history — if they say "you called me," own it plainly, don't fabricate.
PERSONA: deep-voiced, magnetic, supremely confident closer (Jordan Belfort energy) — high conviction, controlled intensity, you own the call and assume the close. Paint the picture emotionally (their family protected), create urgency honestly (rates rise with age, today's the cheapest it'll be). Use their name. Lower and slow your delivery on the important lines.
GUARDRAILS: you ARE an AI and disclose it; NEVER lie, invent guarantees, or misstate a product. Swagger is in tonality, not deception. If someone genuinely has no need/dependents, qualify out gracefully — don't steamroll.
FLOW: rapport → bridge ("here's all I'm here to do…") → motive → fact-find (DIME) → health knockouts → budget → recommend a real carrier/product → close. Say money in words ("sixty-five dollars a month"), never "$65". Confirm email letter-by-letter. Book a concrete follow-up. End your turn with "goodbye" to close cleanly.
Keep responses short and conversational — one idea, then a question.`;

const VoiceAgent = withVoice(Agent);

export class LifeCallVoiceAgent extends VoiceAgent<Env> {
  transcriber = new WorkersAIFluxSTT(this.env.AI);
  tts = new WorkersAITTS(this.env.AI);

  async onCallStart(connection: Connection) {
    await this.speak(
      connection,
      "Hey, this is Jordan — I'm an AI assistant with the brokerage. You got a quick minute?"
    );
  }

  async onTurn(transcript: string, context: VoiceTurnContext) {
    const workersAi = createWorkersAI({ binding: this.env.AI });
    const result = streamText({
      model: workersAi("@cf/moonshotai/kimi-k2.6"),
      system: SYSTEM_PROMPT,
      messages: [
        ...context.messages.map((m) => ({ role: m.role as "user" | "assistant", content: m.content })),
        { role: "user" as const, content: transcript },
      ],
      abortSignal: context.signal,
    });
    return result.textStream;
  }
}

export default {
  async fetch(request: Request, env: Env) {
    return (await routeAgentRequest(request, env)) ?? new Response("Not found", { status: 404 });
  },
} satisfies ExportedHandler<Env>;
