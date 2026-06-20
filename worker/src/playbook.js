// The pipeline engine. A Playbook (authored in-app, stored in D1) drives the live
// call's system prompt, the post-call extraction schema, urgency scoring, and
// document routing. Mirrors Sources/Playbook.swift. The life-insurance playbook
// is the seeded default when an owner hasn't authored one.

export const DEFAULT_PLAYBOOK = {
  id: "life-insurance",
  name: "Life Insurance",
  disclosure:
    "Hey, this is Jordan — I'm an AI assistant with the brokerage, following up on " +
    "the coverage info you requested. A licensed agent reviews everything I set up. " +
    "You got a quick minute?",
  // The script body is owned by the app; the Worker stores whatever was synced.
  personaAndFlow: "You are Jordan, an AI assistant for a licensed life-insurance brokerage. Be warm, confident, and natural; one idea then a question; handle objections; say money in words.",
  collect: [
    { key: "name", prompt: "their full name", priority: "critical" },
    { key: "email", prompt: "best email for paperwork (read it back)", priority: "critical" },
    { key: "phone", prompt: "best callback number in E.164", priority: "critical" },
    { key: "age", prompt: "their age / date of birth", priority: "high" },
    { key: "monthly_budget", prompt: "the final agreed monthly premium", priority: "high" },
    { key: "callback_at", prompt: "a concrete follow-up time", priority: "high" },
    { key: "coverage_amount", prompt: "desired face amount", priority: "normal" },
    { key: "coverage_type", prompt: "term/whole/UL/IUL/final expense", priority: "normal" },
  ],
  urgencyTiers: [
    { name: "Hot", criteria: "agreed to a premium and gave payment intent or said yes to applying", action: "sendDocuments" },
    { name: "Warm", criteria: "qualified and interested but wants to think/compare; gave a callback time", action: "sendDocuments" },
    { name: "Cold", criteria: "not interested, unqualified, or no real engagement", action: "none" },
  ],
  documents: [
    { id: "application", title: "Application & e-Signature", kind: "pdf", forOutcomes: ["booked", "qualified"], forUrgency: ["Hot"] },
    { id: "proposal", title: "Personalized Coverage Proposal", kind: "pdf", forOutcomes: ["booked", "qualified", "callback"], forUrgency: ["Hot", "Warm"] },
    { id: "comparison", title: "Term vs Whole vs IUL Guide", kind: "docx", forOutcomes: ["callback", "qualified"], forUrgency: ["Warm"] },
    { id: "cost_of_waiting", title: "The Real Cost of Waiting", kind: "docx", forOutcomes: ["callback"], forUrgency: ["Warm"] },
  ],
  calendar: { enabled: true, googleCalendar: true, icsInvite: true, meetingTitle: "LifeCall: {name} — coverage review", durationMinutes: 20 },
  autoActionsEnabled: false,
};

const PRIORITY_RANK = { critical: 0, high: 1, normal: 2, optional: 3 };
const PRIORITY_NOTE = {
  critical: "MUST get this — don't wrap the call without it",
  high: "important, chase it",
  normal: "get it if it comes up naturally",
  optional: "nice to have",
};

/// Build the live-call system prompt from a playbook (fields ordered by urgency).
export function buildSystemPrompt(pb) {
  const fields = [...(pb.collect || [])]
    .sort((a, b) => (PRIORITY_RANK[a.priority] ?? 9) - (PRIORITY_RANK[b.priority] ?? 9))
    .map((f) => `- ${f.key}: ${f.prompt} — ${PRIORITY_NOTE[f.priority] || ""}`)
    .join("\n");
  return [
    pb.personaAndFlow,
    `\nDISCLOSE YOU'RE AN AI up front: ${pb.disclosure}`,
    `\nTHINGS TO GET on this call (weave in naturally, don't interrogate):\n${fields}`,
    `\nAlways book the next step before hanging up, confirm contact details by reading them back, and end your turn with the word "goodbye" to close cleanly.`,
  ].join("\n");
}

/// Build the post-call extraction prompt: pull the collect[] fields + summary +
/// fact_find + outcome, and pick the urgency tier by its criteria.
export function buildExtractionPrompt(pb, transcript, nowISO) {
  const keys = (pb.collect || []).map((f) => f.key).join(", ");
  const tiers = (pb.urgencyTiers || []).map((t) => `"${t.name}" (${t.criteria})`).join("; ");
  return `From this sales call transcript, extract a JSON object.
Fields to extract: ${keys}.
For callback_at, if a relative follow-up time was agreed ("in an hour", "tomorrow at 2"), output an absolute ISO 8601 timestamp relative to NOW=${nowISO}; else null.
Also include:
- "outcome": one of qualified, booked, not_interested, callback, unknown
- "summary": 2-3 sentence recap of how the call went
- "fact_find": object of discovery notes (motive, dependents, income, health, objections, recommended_product, etc.; null where unknown)
- "urgency": the single best-fit tier name from: ${tiers}
Respond with ONLY the JSON object.

TRANSCRIPT:
${transcript}`;
}

/// Deterministically route documents for a scored lead.
export function routeDocuments(pb, lead) {
  return pb.documents.filter(
    (d) =>
      (d.forOutcomes || []).includes(lead.outcome) ||
      (d.forUrgency || []).includes(lead.urgency)
  );
}

/// The auto-action a scored lead triggers — only if the playbook enables it.
export function plannedAction(pb, lead) {
  if (!pb.autoActionsEnabled) return "none";
  const tier = (pb.urgencyTiers || []).find((t) => t.name === lead.urgency);
  return tier?.action || "none";
}
