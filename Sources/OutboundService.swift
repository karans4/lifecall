import Foundation

/// Server-side outbound dial via Vapi REST. The AI places a real PSTN call to
/// the number you pass. For the demo we call this straight from the app with the
/// private key; in production this endpoint lives behind your own server.
enum OutboundService {
    struct CallResponse: Decodable { let id: String }

    /// Dials `toNumber` (E.164, e.g. "+14155551234") and runs the intake agent.
    static func dial(toNumber: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.vapi.ai/call")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(Config.vapiPrivateKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "phoneNumberId": Config.vapiPhoneNumberId,
            "customer": ["number": toNumber],
            "assistant": [
                "firstMessage": IntakeScript.firstMessage,
                "model": [
                    "provider": "custom-llm",
                    "url": "https://api.studio.nebius.com/v1",
                    "model": "meta-llama/Llama-3.3-70B-Instruct",
                    "messages": [["role": "system", "content": IntakeScript.systemPrompt]]
                ],
                "voice": [
                    "provider": "openai",
                    "voiceId": "onyx"
                ],
                "startSpeakingPlan": [
                    "waitSeconds": 0.3,
                    "smartEndpointingPlan": ["provider": "livekit"]
                ],
                "endCallPhrases": ["goodbye", "bye", "hang up", "that's all", "we're done"],
                "maxDurationSeconds": 1800,
                "firstMessageInterruptionsEnabled": true,
                "stopSpeakingPlan": ["numWords": 1, "voiceSeconds": 0.2, "backoffSeconds": 1.0]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "Vapi", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(CallResponse.self, from: data).id
    }

    private struct CallRecord: Decodable {
        let status: String?
        let transcript: String?
        let endedReason: String?
    }

    /// Whether a call has ended, and its transcript so far.
    struct CallState { let ended: Bool; let transcript: String }

    /// One-shot fetch of a call's current state from Vapi.
    static func callState(callId: String) async throws -> CallState {
        var req = URLRequest(url: URL(string: "https://api.vapi.ai/call/\(callId)")!)
        req.setValue("Bearer \(Config.vapiPrivateKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Vapi", code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let rec = try JSONDecoder().decode(CallRecord.self, from: data)
        return CallState(ended: rec.status == "ended", transcript: rec.transcript ?? "")
    }
}
