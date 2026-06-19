import Foundation
import Combine
import Vapi

/// Handles the *in-app* live voice conversation (the native flex — you talk to
/// the agent through the phone itself, WebRTC under the hood).
@MainActor
final class VapiManager: ObservableObject {
    enum CallState: Equatable { case idle, connecting, active, ended }

    @Published var state: CallState = .idle
    @Published var transcript: [TranscriptLine] = []
    @Published var leads: [Lead] = []
    @Published var savingLead = false

    struct TranscriptLine: Identifiable {
        let id = UUID()
        let role: String   // "user" or "assistant"
        let text: String
    }

    private let vapi = Vapi(publicKey: Config.vapiPublicKey)
    private var cancellable: AnyCancellable?

    init() {
        cancellable = vapi.eventPublisher.sink { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func start() {
        state = .connecting
        transcript.removeAll()
        Task {
            do {
                // Inline assistant so we don't need a pre-created id to demo.
                let assistant: [String: Any] = [
                    "firstMessage": IntakeScript.firstMessage,
                    "model": [
                        // Nebius Token Factory (OpenAI-compatible) via Vapi custom-llm.
                        "provider": "custom-llm",
                        "url": "https://api.studio.nebius.com/v1",
                        "model": "meta-llama/Llama-3.3-70B-Instruct",
                        "messages": [["role": "system", "content": IntakeScript.systemPrompt]]
                    ],
                    "voice": [
                        "provider": "openai",
                        "voiceId": "onyx"   // deep, confident male — no key needed
                    ],
                    // Respond faster + detect turn-end naturally instead of a fixed pause.
                    "startSpeakingPlan": [
                        "waitSeconds": 0.3,
                        "smartEndpointingPlan": ["provider": "livekit"]
                    ],
                    // Hard backstop: any of these phrases ends the call immediately.
                    "endCallPhrases": ["goodbye", "bye", "hang up", "that's all", "we're done"],
                    // Avoid Vapi's default 10-min cap guillotining a demo call.
                    "maxDurationSeconds": 1800,
                    // Let the user barge in — including over the opening line.
                    "firstMessageInterruptionsEnabled": true,
                    "stopSpeakingPlan": ["numWords": 1, "voiceSeconds": 0.2, "backoffSeconds": 1.0]
                ]
                try await vapi.start(assistant: assistant)
            } catch {
                self.state = .idle
                print("Vapi start failed: \(error)")
            }
        }
    }

    func stop() { vapi.stop() }

    /// On in-app call end: extract a structured lead from the live transcript.
    private func captureLead() {
        let text = transcript.map { "\($0.role): \($0.text)" }.joined(separator: "\n")
        guard !text.isEmpty else { return }
        Task { await runPipeline(on: text) }
    }

    // Outbound calls finish while the app is backgrounded (you answer on the same
    // phone), so a live poll gets suspended. Instead we remember pending call ids
    // and reconcile them whenever the app comes back to the foreground.
    private let pendingKey = "pendingOutboundCallIds"
    private let capturedKey = "capturedOutboundCallIds"
    private var inFlight: Set<String> = []

    private var pendingCallIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: pendingKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: pendingKey) }
    }
    private var capturedCallIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: capturedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: capturedKey) }
    }

    /// Register an outbound call to be captured once it ends.
    func enqueueOutbound(callId: String) {
        pendingCallIds.insert(callId)
        reconcilePending()
    }

    /// Process any pending outbound calls that have finished. Safe to call on every
    /// foreground; each call is captured exactly once.
    func reconcilePending() {
        for callId in pendingCallIds where !inFlight.contains(callId) {
            inFlight.insert(callId)
            Task {
                defer { inFlight.remove(callId) }
                guard !capturedCallIds.contains(callId) else {
                    pendingCallIds.remove(callId); return
                }
                guard let state = try? await OutboundService.callState(callId: callId), state.ended else { return }
                capturedCallIds.insert(callId)
                pendingCallIds.remove(callId)
                if !state.transcript.isEmpty { await runPipeline(on: state.transcript) }
            }
        }
    }

    /// Shared: Nebius extracts a structured lead, saves to Insforge, and — if an
    /// email was captured — picks situation-fit docs and sends the follow-up.
    private func runPipeline(on text: String) async {
        savingLead = true
        do {
            let lead = try await LeadExtractor.extract(from: text)
            try await InsforgeService.save(lead)
            if let email = lead.email, email.contains("@") {
                if let plan = try? await EmailComposer.composeAndSend(to: email, lead: lead, transcript: text) {
                    print("emailed \(plan.documentIds) | followup: \(plan.needsFollowupStage) \(plan.followupNote)")
                }
            }
            self.leads = try await InsforgeService.fetch()
        } catch {
            print("runPipeline failed: \(error)")
        }
        self.savingLead = false
    }

    func refreshLeads() {
        Task { self.leads = (try? await InsforgeService.fetch()) ?? [] }
    }

    @Published var runningCallbacks = false
    @Published var callbackResult = ""

    /// Manual trigger (human-in-the-loop): dial every lead whose callback time has
    /// passed, is still pending, and is on the consented allowlist. You tap to fire.
    func runDueCallbacks() {
        runningCallbacks = true
        callbackResult = ""
        Task {
            let now = Date()
            let iso = ISO8601DateFormatter()
            let all = (try? await InsforgeService.fetch(limit: 100)) ?? []
            let due = all.filter { lead in
                guard let phone = lead.phone, Config.callbackAllowlist.contains(phone) else { return false }
                guard (lead.callbackStatus ?? "pending") == "pending" else { return false }
                guard let at = lead.callbackAt, let d = iso.date(from: at) else { return false }
                return d <= now
            }
            var dialed = 0
            for lead in due {
                guard let phone = lead.phone, let id = lead.id else { continue }
                do {
                    _ = try await OutboundService.dial(toNumber: phone)
                    try? await InsforgeService.update(id: id, fields: ["callback_status": "called"])
                    dialed += 1
                } catch {
                    try? await InsforgeService.update(id: id, fields: ["callback_status": "failed"])
                }
            }
            self.callbackResult = due.isEmpty ? "No callbacks due right now."
                : "Dialed \(dialed) of \(due.count) due callback(s)."
            self.leads = (try? await InsforgeService.fetch()) ?? []
            self.runningCallbacks = false
        }
    }

    private func handle(_ event: Vapi.Event) {
        switch event {
        case .callDidStart:
            state = .active
        case .callDidEnd:
            state = .ended
            captureLead()
        case .transcript(let t):
            transcript.append(.init(role: "\(t.role)", text: t.transcript))
        default:
            break
        }
    }
}
