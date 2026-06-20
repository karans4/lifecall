// LifeCall edge worker — the backend that holds all keys. Adapted from halo's
// edge-worker patterns. Responsibilities:
//   - Verify Sign in with Apple (identity JWT) and mint our own session token
//   - Owner-scoped leads in D1 (no client ever sees another agent's data)
//   - Private PDF storage in R2, served only to the owner
//   - OpenRouter custom-LLM proxy (the endpoint ElevenLabs' agent calls)
//   - Transactional email via Resend
//   - Consent-gated outbound dialing (TCPA)
//
// Keys live only here as Wrangler secrets — never in the client.

import {
  DEFAULT_PLAYBOOK, buildSystemPrompt, buildExtractionPrompt, routeDocuments, plannedAction,
} from "./playbook.js";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,PATCH,OPTIONS",
  "Access-Control-Allow-Headers": "authorization,content-type,x-lifecall-session,x-lifecall-user",
};

const json = (status, body) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...CORS } });
const err = (status, msg) => json(status, { error: msg });

function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

// ---- base64url -------------------------------------------------------------
const b64urlToBytes = (s) => {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  const pad = s.length % 4 ? "=".repeat(4 - (s.length % 4)) : "";
  const bin = atob(s + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
};
const bytesToB64url = (bytes) => {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

// ---- Sign in with Apple verification --------------------------------------
let _jwks = null, _jwksAt = 0;
async function appleKeys() {
  const now = Date.now();
  if (_jwks && now - _jwksAt < 3600_000) return _jwks; // cache 1h
  const res = await fetch("https://appleid.apple.com/auth/keys");
  _jwks = (await res.json()).keys;
  _jwksAt = now;
  return _jwks;
}

/// Verify an Apple identity token. Returns { sub, email } or throws.
async function verifyApple(idToken, bundleId) {
  const [h, p, s] = idToken.split(".");
  if (!h || !p || !s) throw new Error("malformed token");
  const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(h)));
  const payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(p)));

  const jwk = (await appleKeys()).find((k) => k.kid === header.kid);
  if (!jwk) throw new Error("unknown key id");

  const key = await crypto.subtle.importKey(
    "jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]
  );
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5", key, b64urlToBytes(s),
    new TextEncoder().encode(`${h}.${p}`)
  );
  if (!ok) throw new Error("bad signature");

  if (payload.iss !== "https://appleid.apple.com") throw new Error("bad issuer");
  if (payload.aud !== bundleId) throw new Error("bad audience");
  if (payload.exp * 1000 < Date.now()) throw new Error("expired");
  return { sub: payload.sub, email: payload.email };
}

// ---- our session tokens (HMAC) --------------------------------------------
async function hmacKey(secret) {
  return crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]
  );
}
async function mintSession(uid, secret, ttlSec = 60 * 60 * 24 * 30) {
  const exp = Math.floor(Date.now() / 1000) + ttlSec;
  const body = `${uid}.${exp}`;
  const sig = await crypto.subtle.sign("HMAC", await hmacKey(secret), new TextEncoder().encode(body));
  return { token: `${body}.${bytesToB64url(new Uint8Array(sig))}`, expiresIn: ttlSec };
}
async function verifySession(token, secret) {
  if (!token) return null;
  const i = token.lastIndexOf(".");
  if (i < 0) return null;
  const body = token.slice(0, i);
  const sig = token.slice(i + 1);
  const ok = await crypto.subtle.verify(
    "HMAC", await hmacKey(secret), b64urlToBytes(sig), new TextEncoder().encode(body)
  );
  if (!ok) return null;
  const [uid, exp] = body.split(".");
  if (Number(exp) * 1000 < Date.now()) return null;
  return uid;
}

async function requireUser(req, env) {
  const uid = await verifySession(req.headers.get("x-lifecall-session"), env.SESSION_SECRET);
  return uid; // null if missing/invalid
}

// ---- per-user metering -----------------------------------------------------
async function meter(env, uid) {
  if (!env.USAGE) return null;
  const month = new Date().toISOString().slice(0, 7);
  const gKey = `global:${month}`, uKey = `user:${uid}:${month}`;
  const [g, u] = await Promise.all([env.USAGE.get(gKey), env.USAGE.get(uKey)]);
  const gc = Number(g) || 0, uc = Number(u) || 0;
  if (Number(env.GLOBAL_MONTHLY_CAP) && gc >= Number(env.GLOBAL_MONTHLY_CAP))
    return err(503, "LifeCall is at capacity this month.");
  if (Number(env.USER_MONTHLY_CAP) && uc >= Number(env.USER_MONTHLY_CAP))
    return err(429, "You've hit this month's limit.");
  const ttl = 60 * 60 * 24 * 35;
  await Promise.all([
    env.USAGE.put(gKey, String(gc + 1), { expirationTtl: ttl }),
    env.USAGE.put(uKey, String(uc + 1), { expirationTtl: ttl }),
  ]);
  return null;
}

// ---- playbook helpers ------------------------------------------------------
async function activePlaybook(env, owner) {
  try {
    const row = await env.DB.prepare(
      "SELECT json FROM playbooks WHERE owner = ? AND active = 1 LIMIT 1"
    ).bind(owner).first();
    if (row?.json) return JSON.parse(row.json);
  } catch {}
  return DEFAULT_PLAYBOOK;
}

/// Internal non-streaming OpenRouter call (US-pinned), returns message content.
async function callLLM(env, messages, { jsonMode = false } = {}) {
  const body = { model: env.OPENROUTER_MODEL, messages, temperature: 0.2 };
  if (jsonMode) body.response_format = { type: "json_object" };
  if (env.OPENROUTER_PROVIDERS) {
    body.provider = {
      only: env.OPENROUTER_PROVIDERS.split(",").map((s) => s.trim()),
      data_collection: "deny", allow_fallbacks: true,
    };
  }
  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${env.OPENROUTER_API_KEY}` },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  return data?.choices?.[0]?.message?.content ?? "";
}

// ---- routes ----------------------------------------------------------------
export default {
  async fetch(req, env) {
    if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
    const url = new URL(req.url);
    const path = url.pathname;
    try {
      if (req.method === "POST" && path === "/v1/auth") return authRoute(req, env);
      if (req.method === "POST" && path === "/v1/chat/completions") return chatRoute(req, env);
      if (path === "/v1/leads") return leadsRoute(req, env);
      if (req.method === "POST" && path === "/v1/leads/extract") return extractRoute(req, env);
      if (path === "/v1/playbooks") return playbooksRoute(req, env);
      if (req.method === "POST" && path === "/v1/playbooks/activate") return activatePlaybookRoute(req, env);
      if (req.method === "POST" && path === "/v1/documents") return uploadDoc(req, env);
      if (req.method === "GET" && path.startsWith("/v1/documents/")) return serveDoc(req, env, path);
      if (req.method === "POST" && path === "/v1/email") return emailRoute(req, env);
      if (req.method === "POST" && path === "/v1/voice/token") return voiceTokenRoute(req, env);
      if (req.method === "POST" && path === "/v1/voice/clone") return voiceCloneRoute(req, env);
      if (req.method === "POST" && path === "/v1/calls/end") return callEndRoute(req, env);
      if (req.method === "POST" && path === "/v1/dial") return dialRoute(req, env);
      if (req.method === "GET" && path === "/v1/billing/packs") return packsRoute();
      if (req.method === "POST" && path === "/v1/billing/checkout") return checkoutRoute(req, env);
      if (req.method === "GET" && path === "/v1/billing/status") return billingStatusRoute(req, env);
      if (req.method === "POST" && path === "/v1/stripe/webhook") return stripeWebhookRoute(req, env);
      if (req.method === "GET" && path === "/billing/success") return new Response("<h2>You're all set — return to LifeCall.</h2>", { headers: { "content-type": "text/html" } });
      return err(404, "not found");
    } catch (e) {
      return err(500, String(e?.message || e));
    }
  },
};

// POST /v1/auth { identityToken } -> { session, expiresIn, userId }
async function authRoute(req, env) {
  const { identityToken } = await req.json();
  if (!identityToken) return err(400, "identityToken required");
  const { sub } = await verifyApple(identityToken, env.APPLE_BUNDLE_ID);
  const { token, expiresIn } = await mintSession(sub, env.SESSION_SECRET);
  return json(200, { session: token, expiresIn, userId: sub });
}

// POST /v1/chat/completions — OpenRouter proxy. Auth via user session OR the
// ElevenLabs custom-LLM bearer (CUSTOM_LLM_TOKEN). OpenAI-compatible passthrough.
async function chatRoute(req, env) {
  let uid = await requireUser(req, env);
  if (!uid) {
    const m = /^Bearer\s+(.+)$/i.exec(req.headers.get("authorization") || "");
    if (m && env.CUSTOM_LLM_TOKEN && safeEqual(m[1], env.CUSTOM_LLM_TOKEN)) {
      uid = req.headers.get("x-lifecall-user") || "agent";
    }
  }
  if (!uid) return err(401, "unauthorized");
  const limited = await meter(env, uid);
  if (limited) return limited;
  if (!env.OPENROUTER_API_KEY) return err(503, "LLM not configured");

  const body = await req.json();
  if (!body.model || body.model === "default") body.model = env.OPENROUTER_MODEL;

  // Inject the owner's active playbook as the system prompt if the caller (e.g.
  // ElevenLabs' agent) didn't already supply one. This is what makes the live
  // call follow the configured script.
  const msgs = body.messages || [];
  if (!msgs.some((m) => m.role === "system") && uid !== "agent") {
    const pb = await activePlaybook(env, uid);
    body.messages = [{ role: "system", content: buildSystemPrompt(pb) }, ...msgs];
  }

  // Pin to US-based inference hosts and forbid any provider that logs/trains on
  // prompts — keeps the (open-weight) model's data on US soil for PII compliance.
  if (env.OPENROUTER_PROVIDERS) {
    body.provider = {
      only: env.OPENROUTER_PROVIDERS.split(",").map((s) => s.trim()),
      data_collection: "deny",
      allow_fallbacks: true,
    };
  }
  const upstream = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${env.OPENROUTER_API_KEY}`,
      "HTTP-Referer": env.OPENROUTER_REFERER || "",
      "X-Title": "LifeCall",
    },
    body: JSON.stringify(body),
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": upstream.headers.get("content-type") || "application/json", ...CORS },
  });
}

// GET /v1/leads -> owner's leads ; POST /v1/leads { lead } -> upsert
async function leadsRoute(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");

  if (req.method === "GET") {
    const { results } = await env.DB.prepare(
      "SELECT * FROM leads WHERE owner = ? ORDER BY created_at DESC LIMIT 50"
    ).bind(uid).all();
    return json(200, results.map(rowToLead));
  }
  if (req.method === "POST") {
    const l = await req.json();
    const id = l.id || crypto.randomUUID();
    const createdAt = l.created_at || new Date().toISOString();
    await env.DB.prepare(
      `INSERT INTO leads (id,owner,name,age,coverage_type,coverage_amount,monthly_budget,outcome,
        email,phone,callback_at,callback_status,transcript,summary,fact_find,created_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET name=excluded.name, age=excluded.age,
        coverage_type=excluded.coverage_type, coverage_amount=excluded.coverage_amount,
        monthly_budget=excluded.monthly_budget, outcome=excluded.outcome, email=excluded.email,
        phone=excluded.phone, callback_at=excluded.callback_at, transcript=excluded.transcript,
        summary=excluded.summary, fact_find=excluded.fact_find`
    ).bind(
      id, uid, l.name ?? null, l.age ?? null, l.coverage_type ?? null, l.coverage_amount ?? null,
      l.monthly_budget ?? null, l.outcome ?? null, l.email ?? null, l.phone ?? null,
      l.callback_at ?? null, l.callback_status ?? "pending", l.transcript ?? null,
      l.summary ?? null, l.fact_find ? JSON.stringify(l.fact_find) : null, createdAt
    ).run();
    return json(200, { id });
  }
  return err(405, "method not allowed");
}

const rowToLead = (r) => ({ ...r, fact_find: r.fact_find ? JSON.parse(r.fact_find) : null });

// POST /v1/leads/extract { transcript } — the playbook-driven pipeline:
// extract collect[] fields + summary + fact_find + outcome, score urgency, route
// documents, save the lead, and report the planned auto-action.
async function extractRoute(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  const { transcript } = await req.json();
  if (!transcript) return err(400, "transcript required");
  if (!env.OPENROUTER_API_KEY) return err(503, "LLM not configured");

  const pb = await activePlaybook(env, uid);
  const nowISO = new Date().toISOString();
  const content = await callLLM(env, [
    { role: "user", content: buildExtractionPrompt(pb, transcript, nowISO) },
  ], { jsonMode: true });

  let lead;
  try { lead = JSON.parse(content); } catch { return err(502, "extraction parse failed"); }
  // Skip dead/no-audio calls.
  if (!lead.name && !lead.email && !lead.phone) return json(200, { skipped: true });

  const id = crypto.randomUUID();
  lead.id = id;
  await env.DB.prepare(
    `INSERT INTO leads (id,owner,name,age,coverage_type,coverage_amount,monthly_budget,outcome,
      email,phone,callback_at,callback_status,transcript,summary,fact_find,urgency,playbook_id,created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
  ).bind(
    id, uid, lead.name ?? null, lead.age ?? null, lead.coverage_type ?? null,
    lead.coverage_amount ?? null, lead.monthly_budget ?? null, lead.outcome ?? null,
    lead.email ?? null, lead.phone ?? null, lead.callback_at ?? null, "pending",
    transcript, lead.summary ?? null, lead.fact_find ? JSON.stringify(lead.fact_find) : null,
    lead.urgency ?? null, pb.id, nowISO
  ).run();

  const documents = routeDocuments(pb, lead);
  const action = plannedAction(pb, lead);   // execution (email/book/dial) wired in later phases
  return json(200, { lead, urgency: lead.urgency, documents, action });
}

// GET /v1/playbooks -> owner's playbooks ; POST upsert { id, json, active }
async function playbooksRoute(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  if (req.method === "GET") {
    const { results } = await env.DB.prepare(
      "SELECT id, json, active FROM playbooks WHERE owner = ?"
    ).bind(uid).all();
    const list = results.map((r) => ({ ...JSON.parse(r.json), active: !!r.active }));
    return json(200, list.length ? list : [{ ...DEFAULT_PLAYBOOK, active: true }]);
  }
  if (req.method === "POST") {
    const pb = await req.json();
    if (!pb.id) return err(400, "playbook id required");
    await env.DB.prepare(
      `INSERT INTO playbooks (id, owner, json, active, updated_at) VALUES (?,?,?,?,?)
       ON CONFLICT(owner, id) DO UPDATE SET json=excluded.json, updated_at=excluded.updated_at`
    ).bind(pb.id, uid, JSON.stringify(pb), pb.active ? 1 : 0, new Date().toISOString()).run();
    return json(200, { id: pb.id });
  }
  return err(405, "method not allowed");
}

// POST /v1/playbooks/activate { id } — exactly one active per owner.
async function activatePlaybookRoute(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  const { id } = await req.json();
  if (!id) return err(400, "id required");
  await env.DB.batch([
    env.DB.prepare("UPDATE playbooks SET active = 0 WHERE owner = ?").bind(uid),
    env.DB.prepare("UPDATE playbooks SET active = 1 WHERE owner = ? AND id = ?").bind(uid, id),
  ]);
  return json(200, { active: id });
}

// POST /v1/documents (multipart 'file', ?key=) -> { url } (owner-scoped private)
async function uploadDoc(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  const form = await req.formData();
  const file = form.get("file");
  if (!file) return err(400, "file required");
  const id = crypto.randomUUID();
  const objectKey = `${uid}/${id}.pdf`; // namespaced by owner — not guessable across users
  await env.DOCS.put(objectKey, file.stream(), {
    httpMetadata: { contentType: "application/pdf" },
  });
  // Return a URL to OUR route, which checks ownership before serving.
  return json(200, { url: `${new URL(req.url).origin}/v1/documents/${id}`, id });
}

// GET /v1/documents/:id — serve only to the owner (session required).
async function serveDoc(req, env, path) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  const id = path.split("/").pop();
  const obj = await env.DOCS.get(`${uid}/${id}.pdf`);
  if (!obj) return err(404, "not found");
  return new Response(obj.body, {
    headers: { "content-type": "application/pdf", "cache-control": "private, no-store", ...CORS },
  });
}

// POST /v1/email { to, subject, html } — via Resend, session-gated.
async function emailRoute(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  if (!env.RESEND_API_KEY) return err(503, "email not configured");
  const { to, subject, html } = await req.json();
  if (!to || !subject || !html) return err(400, "to, subject, html required");
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ from: env.EMAIL_FROM, to, subject, html }),
  });
  if (!res.ok) return err(502, `email send failed: ${res.status}`);
  return json(200, { sent: true });
}

// POST /v1/voice/token { agentId } — mint an ElevenLabs conversation token for a
// private agent, server-side (the ElevenLabs key never reaches the device).
async function voiceTokenRoute(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  if (!env.ELEVENLABS_API_KEY) return err(503, "voice not configured");
  const { agentId } = await req.json();
  if (!agentId) return err(400, "agentId required");

  // Gate on balance — need at least a minute of call time. Actual seconds are
  // debited on call end (/v1/calls/end). No charge if balance is too low.
  const row = await env.DB.prepare("SELECT credit_seconds FROM subscriptions WHERE owner = ?").bind(uid).first();
  if ((row?.credit_seconds || 0) < MIN_START_SECONDS) return err(402, "out of call time — buy more hours");

  const res = await fetch(
    `https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=${encodeURIComponent(agentId)}`,
    { headers: { "xi-api-key": env.ELEVENLABS_API_KEY } }
  );
  if (!res.ok) return err(502, `token mint failed: ${res.status}`);
  const data = await res.json();
  return json(200, { token: data.token });
}

// POST /v1/calls/end { seconds } — debit talk time when a call ends. (Client-
// reported for now; can be made ElevenLabs-authoritative via the conversation API.)
async function callEndRoute(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  const { seconds } = await req.json();
  const s = Math.max(0, Math.round(Number(seconds) || 0));
  if (s === 0) return json(200, { credit_seconds: 0 });
  // Floor at 0 so a long call can't drive the balance negative.
  await env.DB.prepare(
    "UPDATE subscriptions SET credit_seconds = MAX(0, credit_seconds - ?), updated_at = ? WHERE owner = ?"
  ).bind(s, new Date().toISOString(), uid).run();
  const row = await env.DB.prepare("SELECT credit_seconds FROM subscriptions WHERE owner = ?").bind(uid).first();
  return json(200, { credit_seconds: row?.credit_seconds || 0 });
}

// POST /v1/voice/clone (multipart: file=audio, attest="true", agentId) — consented
// SELF-clone only. Creates an ElevenLabs instant voice clone from the signed-in
// user's own recording and sets it as their agent's voice. The `attest` flag is the
// user's confirmation that it's their own voice (ToS + consent requirement).
async function voiceCloneRoute(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  if (!env.ELEVENLABS_API_KEY) return err(503, "voice not configured");

  const form = await req.formData();
  const file = form.get("file");
  const attest = form.get("attest");
  const agentId = form.get("agentId");
  if (!file) return err(400, "audio file required");
  if (attest !== "true") return err(403, "consent attestation required (own voice only)");

  // Create the instant voice clone.
  const elForm = new FormData();
  elForm.append("name", `lifecall-${uid.slice(0, 12)}`);
  elForm.append("files", file, "sample.m4a");
  elForm.append("remove_background_noise", "true");
  const cloneRes = await fetch("https://api.elevenlabs.io/v1/voices/add", {
    method: "POST",
    headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
    body: elForm,
  });
  if (!cloneRes.ok) return err(502, `clone failed: ${cloneRes.status} ${await cloneRes.text()}`);
  const { voice_id } = await cloneRes.json();

  // Remember the user's voice.
  if (env.USAGE) await env.USAGE.put(`voice:${uid}`, voice_id);

  // Point the agent at the cloned voice (single-rep model; per-user override is a
  // follow-up). agentId comes from the client config.
  if (agentId) {
    await fetch(`https://api.elevenlabs.io/v1/convai/agents/${agentId}`, {
      method: "PATCH",
      headers: { "xi-api-key": env.ELEVENLABS_API_KEY, "content-type": "application/json" },
      body: JSON.stringify({ conversation_config: { tts: { voice_id } } }),
    });
  }
  return json(200, { voice_id });
}

// POST /v1/dial { to } — consent-gated outbound. Requires a recorded consent row.
// Actual call placement (Twilio + ElevenLabs agent) is wired in the next phase.
async function dialRoute(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  const { to } = await req.json();
  if (!to) return err(400, "to required");
  const row = await env.DB.prepare(
    "SELECT phone FROM consents WHERE owner = ? AND phone = ?"
  ).bind(uid, to).first();
  if (!row) return err(403, "no consent on file for this number");
  // TODO(phase 2): trigger ElevenLabs agent outbound call via Twilio.
  return json(501, { error: "dialing not yet wired", consent: "ok" });
}

// ---- billing (Stripe) — prepaid CALL HOURS, volume pricing -----------------
// Per-hour price declines from $20 toward a $9/hr floor as packs get bigger.
// Calls debit actual seconds of talk time. Edit freely; this is the price sheet.
const MIN_START_SECONDS = 60;  // need at least a minute of balance to start a call
const CREDIT_PACKS = [
  { id: "1hr",   hours: 1,   price_cents: 2000 },  // $20/hr
  { id: "5hr",   hours: 5,   price_cents: 9000 },  // $18/hr
  { id: "20hr",  hours: 20,  price_cents: 28000 }, // $14/hr
  { id: "50hr",  hours: 50,  price_cents: 55000 }, // $11/hr
  { id: "100hr", hours: 100, price_cents: 90000 }, // $9/hr (floor)
];

const bytesToHex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");

/// POST to Stripe's form-encoded API with the secret key.
async function stripe(env, path, params) {
  const body = new URLSearchParams(params).toString();
  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: "POST",
    headers: {
      authorization: "Basic " + btoa(env.STRIPE_SECRET + ":"),
      "content-type": "application/x-www-form-urlencoded",
    },
    body,
  });
  return res.json();
}

// GET /v1/billing/packs -> the price sheet (hours, price, per-hour).
function packsRoute() {
  return json(200, CREDIT_PACKS.map((p) => ({
    ...p, per_hour_cents: Math.round(p.price_cents / p.hours),
  })));
}

// POST /v1/billing/checkout { packId } -> { url } : one-time Checkout for a credit
// pack, tied to the Apple sub. Pay on the web → 0% to Apple.
async function checkoutRoute(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  if (!env.STRIPE_SECRET) return err(503, "billing not configured");
  const { packId } = await req.json();
  const pack = CREDIT_PACKS.find((p) => p.id === packId);
  if (!pack) return err(400, "unknown pack");

  // Reuse or create the account's Stripe customer.
  let row = await env.DB.prepare("SELECT stripe_customer_id FROM subscriptions WHERE owner = ?").bind(uid).first();
  let customer = row?.stripe_customer_id;
  if (!customer) {
    const c = await stripe(env, "customers", { "metadata[apple_sub]": uid });
    customer = c.id;
    await env.DB.prepare(
      "INSERT INTO subscriptions (owner, stripe_customer_id, updated_at) VALUES (?,?,?) ON CONFLICT(owner) DO UPDATE SET stripe_customer_id=excluded.stripe_customer_id"
    ).bind(uid, customer, new Date().toISOString()).run();
  }
  const origin = new URL(req.url).origin;
  const session = await stripe(env, "checkout/sessions", {
    mode: "payment",
    customer,
    "line_items[0][price_data][currency]": "usd",
    "line_items[0][price_data][unit_amount]": String(pack.price_cents),
    "line_items[0][price_data][product_data][name]": `LifeCall — ${pack.hours} hours of call time`,
    "line_items[0][quantity]": "1",
    client_reference_id: uid,
    "payment_intent_data[metadata][apple_sub]": uid,
    "payment_intent_data[metadata][credit_seconds]": String(pack.hours * 3600),
    "metadata[apple_sub]": uid,
    "metadata[credit_seconds]": String(pack.hours * 3600),
    success_url: `${origin}/billing/success`,
    cancel_url: `${origin}/billing/success`,
  });
  if (!session.url) return err(502, "checkout failed: " + JSON.stringify(session).slice(0, 200));
  return json(200, { url: session.url });
}

// GET /v1/billing/status -> { seconds, can_call }
async function billingStatusRoute(req, env) {
  const uid = await requireUser(req, env);
  if (!uid) return err(401, "unauthorized");
  const row = await env.DB.prepare("SELECT credit_seconds FROM subscriptions WHERE owner = ?").bind(uid).first();
  const seconds = row?.credit_seconds || 0;
  return json(200, { seconds, can_call: seconds >= MIN_START_SECONDS });
}

// POST /v1/stripe/webhook — verify signature, credit the account on purchase.
async function stripeWebhookRoute(req, env) {
  const sig = req.headers.get("stripe-signature") || "";
  const raw = await req.text();
  const parts = Object.fromEntries(sig.split(",").map((kv) => kv.split("=")));
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(env.STRIPE_WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${parts.t}.${raw}`));
  if (bytesToHex(mac) !== parts.v1) return err(400, "bad signature");

  const event = JSON.parse(raw);
  if (event.type === "checkout.session.completed") {
    const obj = event.data.object;
    const uid = obj.metadata?.apple_sub || obj.client_reference_id;
    const add = parseInt(obj.metadata?.credit_seconds || "0", 10);
    if (uid && add > 0) {
      const now = new Date().toISOString();
      await env.DB.prepare(
        `INSERT INTO subscriptions (owner, stripe_customer_id, credit_seconds, updated_at) VALUES (?,?,?,?)
         ON CONFLICT(owner) DO UPDATE SET credit_seconds = credit_seconds + ?, updated_at = ?`
      ).bind(uid, obj.customer || null, add, now, add, now).run();
    }
  }
  return json(200, { received: true });
}
