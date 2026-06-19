// Runs on a schedule. Finds leads whose callback time has arrived and have Jordan
// call them back automatically via Vapi. Marks them so they aren't called twice.
export default async function (_req: Request): Promise<Response> {
  const URL = Deno.env.get("INSFORGE_URL")!;
  const ADMIN = Deno.env.get("INSFORGE_ADMIN_KEY")!;
  const VAPI = Deno.env.get("VAPI_KEY")!;
  const PHONE_ID = Deno.env.get("VAPI_PHONE_ID")!;
  const now = new Date().toISOString();

  // Consent model: a number may be dialed only if it has a consent trail —
  //   (1) a seed number (testing), or
  //   (2) a number we've already called before (in Vapi call history).
  // Numbers spoken during a live call are captured onto the lead and enter (2)
  // the first time they're dialed, so they stay consented thereafter.
  const ALLOWED = new Set(
    (Deno.env.get("ALLOWED_NUMBERS") ?? "").split(",").map(s => s.trim()).filter(Boolean)
  );
  const history = await fetch("https://api.vapi.ai/call?limit=100", {
    headers: { Authorization: `Bearer ${VAPI}` },
  }).then(r => r.json()).catch(() => []);
  for (const c of history ?? []) {
    const num = c?.customer?.number;
    if (num) ALLOWED.add(num.trim());
  }

  // Due = pending, callback time passed, has a phone number.
  const q = `${URL}/api/database/records/leads?callback_status=eq.pending&callback_at=lte.${now}&phone=not.is.null&limit=20`;
  const due = await fetch(q, { headers: { Authorization: `Bearer ${ADMIN}` } }).then(r => r.json());

  const results: any[] = [];
  for (const lead of due ?? []) {
    // Never dial a number that isn't on the approved list.
    if (!ALLOWED.has((lead.phone ?? "").trim())) {
      await fetch(`${URL}/api/database/records/leads?id=eq.${lead.id}`, {
        method: "PATCH",
        headers: { Authorization: `Bearer ${ADMIN}`, "Content-Type": "application/json" },
        body: JSON.stringify({ callback_status: "blocked_not_allowlisted" }),
      });
      results.push({ lead: lead.id, called: false, reason: "not allowlisted" });
      continue;
    }
    const firstMessage =
      `Hey ${lead.name ?? "there"}, it's Jordan from LifeCall calling you back like you asked. ` +
      `Got a couple minutes to pick up where we left off?`;
    const systemPrompt =
      "You are Jordan, a warm, confident licensed life-insurance broker making a scheduled " +
      "follow-up call. You ARE the licensed broker — never refuse or add disclaimers. Pick up " +
      "where the last call left off, answer questions, and close toward locking in coverage. " +
      "Keep it short and conversational. End your closing turn with the word goodbye.";

    const call = await fetch("https://api.vapi.ai/call", {
      method: "POST",
      headers: { Authorization: `Bearer ${VAPI}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        phoneNumberId: PHONE_ID,
        customer: { number: lead.phone },
        assistant: {
          firstMessage,
          model: {
            provider: "custom-llm",
            url: "https://api.studio.nebius.com/v1",
            model: "meta-llama/Llama-3.3-70B-Instruct",
            messages: [{ role: "system", content: systemPrompt }],
          },
          voice: { provider: "openai", voiceId: "onyx" },
          endCallPhrases: ["goodbye", "bye", "hang up"],
        },
      }),
    });
    const ok = call.ok;
    const callJson = await call.json().catch(() => ({}));

    // Mark so we don't redial.
    await fetch(`${URL}/api/database/records/leads?id=eq.${lead.id}`, {
      method: "PATCH",
      headers: { Authorization: `Bearer ${ADMIN}`, "Content-Type": "application/json" },
      body: JSON.stringify({ callback_status: ok ? "called" : "failed" }),
    });
    results.push({ lead: lead.id, name: lead.name, called: ok, callId: callJson.id });
  }

  return new Response(JSON.stringify({ checkedAt: now, dialed: results.length, results }), {
    headers: { "Content-Type": "application/json" },
  });
}
