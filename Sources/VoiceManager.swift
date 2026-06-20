import Foundation
import Combine
import ElevenLabs

/// In-app live voice via ElevenLabs Conversational AI (replaces Vapi). The agent
/// runs on ElevenLabs (STT + turn-taking + premium TTS); its LLM is our Worker's
/// OpenRouter proxy. The private-agent session is authorized by a short-lived
/// conversation token minted by the Worker — no ElevenLabs key on the device.
@MainActor
final class VoiceManager: ObservableObject {
    enum CallState: Equatable { case idle, connecting, active, ended }

    @Published var state: CallState = .idle
    @Published var transcript: [TranscriptLine] = []
    @Published var leads: [Lead] = []
    @Published var savingLead = false
    @Published var runningCallbacks = false
    @Published var callbackResult = ""

    struct TranscriptLine: Identifiable {
        let id = UUID()
        let role: String   // "user" or "assistant"
        let text: String
    }

    private var conversation: Conversation?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        state = .connecting
        transcript.removeAll()
        Task {
            do {
                let convo = try await ElevenLabs.startConversation(
                    tokenProvider: { try await WorkerAPI.voiceToken() }
                )
                self.conversation = convo
                observe(convo)
            } catch {
                self.state = .idle
                print("voice start failed: \(error)")
            }
        }
    }

    func stop() { Task { await conversation?.endConversation() } }

    private func observe(_ convo: Conversation) {
        cancellables.removeAll()
        convo.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] st in self?.handleState(st) }
            .store(in: &cancellables)
        convo.$messages
            .receive(on: RunLoop.main)
            .sink { [weak self] msgs in
                self?.transcript = msgs.map {
                    TranscriptLine(role: $0.role == .agent ? "assistant" : "user", text: $0.content)
                }
            }
            .store(in: &cancellables)
    }

    private func handleState(_ st: ConversationState) {
        switch st {
        case .idle:       state = .idle
        case .connecting: state = .connecting
        case .active:     state = .active
        case .ended:      state = .ended; captureLead()
        case .error:      state = .idle
        }
    }

    /// On call end: extract a structured lead, save it, and send the follow-up.
    private func captureLead() {
        let text = transcript.map { "\($0.role): \($0.text)" }.joined(separator: "\n")
        guard !text.isEmpty else { return }
        Task { await runPipeline(on: text) }
    }

    private func runPipeline(on text: String) async {
        savingLead = true
        do {
            let lead = try await LeadExtractor.extract(from: text)
            // Skip dead/no-audio calls — don't save empty leads.
            guard lead.name != nil || lead.email != nil || lead.phone != nil else {
                savingLead = false; return
            }
            try await WorkerAPI.saveLead(lead)
            if let email = lead.email, email.contains("@") {
                _ = try? await EmailComposer.composeAndSend(to: email, lead: lead, transcript: text)
            }
            self.leads = try await WorkerAPI.fetchLeads()
        } catch {
            print("pipeline failed: \(error)")
        }
        savingLead = false
    }

    func refreshLeads() {
        Task { self.leads = (try? await WorkerAPI.fetchLeads()) ?? [] }
    }

    /// Outbound dial — the Worker enforces consent (TCPA) before placing the call.
    func dial(to number: String) async throws {
        try await WorkerAPI.dial(to: number)
    }

    /// Trigger calls for any lead whose callback time has passed.
    func runDueCallbacks() {
        runningCallbacks = true
        callbackResult = ""
        Task {
            let now = Date()
            let due = leads.filter { l in
                guard let iso = l.callbackAt, let d = ScheduleView.parse(iso) else { return false }
                return d <= now && (l.callbackStatus ?? "pending") == "pending"
            }
            var dialed = 0
            for l in due {
                if let p = l.phone, !p.isEmpty, (try? await WorkerAPI.dial(to: p)) != nil { dialed += 1 }
            }
            callbackResult = due.isEmpty ? "No callbacks due." : "Triggered \(dialed) of \(due.count) due."
            runningCallbacks = false
        }
    }
}
