import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var voice = VoiceManager()
    @State private var dialNumber = "+1"
    @State private var dialStatus = ""
    @State private var isDialing = false
    @State private var pulse = false
    @State private var selectedLead: Lead?
    @State private var showVoiceClone = false

    private var isLive: Bool { voice.state == .active }

    var body: some View {
        TabView {
            homeTab
                .tabItem { Label("Home", systemImage: "phone.fill") }
            ScheduleView(leads: voice.leads, onSelect: { selectedLead = $0 })
                .tabItem { Label("Schedule", systemImage: "calendar") }
        }
        .tint(.cyan)
        .preferredColorScheme(.dark)
        .onAppear { voice.refreshLeads() }
        .sheet(item: $selectedLead) { lead in
            LeadDetailView(lead: lead)
        }
    }

    private var homeTab: some View {
        ZStack {
            // Premium dark gradient backdrop.
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.06, blue: 0.12),
                         Color(red: 0.02, green: 0.02, blue: 0.05)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    header
                    callOrb
                    if !voice.transcript.isEmpty { transcriptCard }
                    outboundCard
                    leadsCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            // Tap anywhere that isn't the text field / a control dismisses the keyboard.
            .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title2.bold())
                    .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                Text("LifeCall")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text("Your AI life-insurance closer")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.top, 8)
    }

    // MARK: - Call orb (in-app voice)

    private var callOrb: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(isLive
                          ? AnyShapeStyle(LinearGradient(colors: [.red, .pink], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .frame(width: 168, height: 168)
                    .shadow(color: (isLive ? Color.red : Color.cyan).opacity(0.5), radius: 30)
                    .scaleEffect(pulse && isLive ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)

                VStack(spacing: 8) {
                    Image(systemName: isLive ? "waveform" : "mic.fill")
                        .font(.system(size: 46, weight: .semibold))
                    Text(orbLabel)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
            }
            .onTapGesture { toggleCall(); pulse = true }

            Text(isLive ? "Tap to end • talk anytime, you can interrupt" : "Tap to talk to Jordan")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))

            Button { showVoiceClone = true } label: {
                Label("Use my voice", systemImage: "waveform.badge.mic")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.cyan)
            }
            .sheet(isPresented: $showVoiceClone) { VoiceCloneView() }
        }
        .padding(.vertical, 8)
    }

    private var orbLabel: String {
        switch voice.state {
        case .idle, .ended: return "Start"
        case .connecting:   return "Connecting"
        case .active:       return "End"
        }
    }

    // MARK: - Transcript

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Live transcript", systemImage: "text.bubble.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.cyan)
            ForEach(voice.transcript) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text(line.role == "user" ? "🧑" : "🤖")
                    Text(line.text)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .background(card)
    }

    // MARK: - Outbound

    private var outboundCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Have Jordan call leads", systemImage: "phone.arrow.up.right.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.green)

            TextField("", text: $dialNumber,
                      prompt: Text("+1 415 555 0123, +1 414 555 0199").foregroundColor(.white.opacity(0.3)),
                      axis: .vertical)
                .font(.title3.monospacedDigit())
                .foregroundStyle(.white)
                .keyboardType(.phonePad)
                .lineLimit(1...4)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))

            Text("Comma- or line-separated to call several at once.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))

            Button(action: dial) {
                HStack {
                    if isDialing { ProgressView().tint(.white) }
                    Text(isDialing ? "Dialing…" : "Call these numbers")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(15)
                .background(LinearGradient(colors: [.green, Color(red: 0.1, green: 0.6, blue: 0.3)],
                                           startPoint: .leading, endPoint: .trailing))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isDialing)

            if !dialStatus.isEmpty {
                Text(dialStatus)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(18)
        .background(card)
    }

    // MARK: - Leads

    private var leadsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Captured leads", systemImage: "person.crop.rectangle.stack.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.purple)
                Spacer()
                if voice.savingLead {
                    HStack(spacing: 6) {
                        ProgressView().tint(.purple).scaleEffect(0.8)
                        Text("Saving…").font(.caption).foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    Button { voice.refreshLeads() } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(.white.opacity(0.6))
                    }
                }
            }

            Button(action: { voice.runDueCallbacks() }) {
                HStack {
                    if voice.runningCallbacks { ProgressView().tint(.white) }
                    Image(systemName: "phone.badge.waveform.fill")
                    Text(voice.runningCallbacks ? "Dialing due callbacks…" : "Run due callbacks")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(voice.runningCallbacks)
            if !voice.callbackResult.isEmpty {
                Text(voice.callbackResult).font(.caption).foregroundStyle(.white.opacity(0.6))
            }

            if voice.leads.isEmpty {
                Text("Leads land here after each call — auto-extracted from the conversation.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(voice.leads) { lead in
                    Button { selectedLead = lead } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(lead.name ?? "Unknown")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(lead.outcome ?? "—")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(outcomeColor(lead.outcome).opacity(0.25))
                                    .foregroundStyle(outcomeColor(lead.outcome))
                                    .clipShape(Capsule())
                            }
                            Text(leadDetail(lead))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                            if let cb = lead.callbackAt, !cb.isEmpty {
                                Label(LeadDetailView.prettyDate(cb), systemImage: "calendar.badge.clock")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(card)
    }

    private func leadDetail(_ l: Lead) -> String {
        [l.age.map { "Age \($0)" }, l.coverageType, l.coverageAmount, l.monthlyBudget]
            .compactMap { $0 }.joined(separator: " • ")
    }

    private func outcomeColor(_ outcome: String?) -> Color {
        switch outcome {
        case "booked", "qualified": return .green
        case "callback":            return .orange
        case "not_interested":      return .red
        default:                    return .gray
        }
    }

    // MARK: - Shared

    private var card: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private func toggleCall() {
        isLive ? voice.stop() : voice.start()
    }

    private func dial() {
        // Accept one or many numbers: split on commas, semicolons, or newlines.
        let numbers = dialNumber
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !numbers.isEmpty else { dialStatus = "Enter a phone number"; return }

        isDialing = true
        dialStatus = ""
        Task {
            var placed = 0
            var failed = 0
            for number in numbers {
                do {
                    try await voice.dial(to: number)   // Worker enforces consent (TCPA)
                    placed += 1
                } catch {
                    failed += 1
                }
            }
            dialStatus = failed == 0
                ? "Placed \(placed) call\(placed == 1 ? "" : "s") ✓ — lead lands when it ends"
                : "Placed \(placed) ✓  ·  \(failed) failed (need consent on file)"
            isDialing = false
        }
    }
}
