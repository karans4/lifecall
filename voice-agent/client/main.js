import { VoiceClient } from "@cloudflare/voice/client";

const client = new VoiceClient({
  agent: "LifeCallVoiceAgent",
  host: "lifecall-voice.karans4.workers.dev",
});

const statusEl = document.getElementById("status");
const logEl = document.getElementById("log");

client.on("statuschange", (s) => { statusEl.textContent = s; });
client.on("error", (e) => { if (e) logEl.insertAdjacentHTML("beforeend", `<div class="err">error: ${e}</div>`); });
client.on("transcriptchange", (msgs) => {
  logEl.innerHTML = msgs.map((m) => `<div><b>${m.role}:</b> ${m.text}</div>`).join("");
});
client.on("interimtranscript", (t) => { if (t) statusEl.textContent = "…" + t; });

document.getElementById("start").onclick = () =>
  client.startCall().catch((e) => { statusEl.textContent = "start failed: " + e; });
document.getElementById("stop").onclick = () => client.endCall();
document.getElementById("mute").onclick = () => client.toggleMute();
