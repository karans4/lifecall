import SwiftUI
import AVFoundation

/// "Use my voice" — record a short sample of YOUR OWN voice and clone it so Jordan
/// speaks in it. Consent is explicit (the toggle); the Worker only ever clones the
/// signed-in user's own recording.
@MainActor
final class VoiceCloneRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed = 0
    @Published var status = ""
    @Published var done = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var fileURL: URL?

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .default)
        try? session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-sample.m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        fileURL = url
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed += 1
                if self.elapsed >= 60 { self.stop() }   // cap at 60s
            }
        }
    }

    func stop() {
        recorder?.stop()
        timer?.invalidate()
        isRecording = false
    }

    /// Upload the recording to clone the voice and set it on the agent.
    func clone() async {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else {
            status = "No recording found."; return
        }
        status = "Cloning your voice…"
        do {
            _ = try await WorkerAPI.cloneVoice(data, agentId: Config.elevenLabsAgentId)
            status = "Done — Jordan now speaks in your voice."
            done = true
        } catch {
            status = "Clone failed: \(error)"
        }
    }
}

struct VoiceCloneView: View {
    @StateObject private var rec = VoiceCloneRecorder()
    @State private var consent = false
    @Environment(\.dismiss) private var dismiss

    private var canClone: Bool { consent && rec.fileURL != nil && !rec.isRecording && rec.elapsed >= 10 }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.12),
                                        Color(red: 0.02, green: 0.02, blue: 0.05)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("Use my voice")
                        .font(.title.bold()).foregroundStyle(.white)
                    Text("Record 10–60 seconds of yourself talking naturally. Jordan will speak in your cloned voice on calls.")
                        .font(.subheadline).multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.6)).padding(.horizontal)

                    Button(action: { rec.isRecording ? rec.stop() : rec.start() }) {
                        ZStack {
                            Circle().fill(rec.isRecording ? Color.red : Color.cyan)
                                .frame(width: 120, height: 120)
                            Image(systemName: rec.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 44)).foregroundStyle(.white)
                        }
                    }
                    Text(rec.isRecording ? "Recording… \(rec.elapsed)s (tap to stop)"
                         : rec.fileURL != nil ? "Recorded \(rec.elapsed)s" : "Tap to record")
                        .font(.footnote).foregroundStyle(.white.opacity(0.55))

                    Toggle(isOn: $consent) {
                        Text("I confirm this is my own voice and I consent to cloning it.")
                            .font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                    .tint(.cyan).padding(.horizontal)

                    Button {
                        Task { await rec.clone() }
                    } label: {
                        Text("Clone my voice").fontWeight(.semibold).frame(maxWidth: .infinity).padding(14)
                            .background(canClone ? Color.cyan : Color.gray.opacity(0.4))
                            .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canClone).padding(.horizontal)

                    if !rec.status.isEmpty {
                        Text(rec.status).font(.footnote).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(.top, 40)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: rec.done) { _, done in if done { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }
}
