import Foundation

/// The single client for the LifeCall Worker. Attaches the Sign in with Apple
/// session token. No provider keys ever touch the device — the Worker holds them.
enum WorkerAPI {
    struct APIError: Error { let status: Int; let body: String }

    /// The session token minted by the Worker's /v1/auth (set by AuthStore after
    /// Sign in with Apple). nil until signed in.
    static var session: String? {
        get { UserDefaults.standard.string(forKey: "auth.session") }
        set { UserDefaults.standard.set(newValue, forKey: "auth.session") }
    }

    private static func request(_ path: String, method: String = "GET", json body: Any? = nil) async throws -> Data {
        var req = URLRequest(url: URL(string: "\(Config.workerBaseURL)\(path)")!)
        req.httpMethod = method
        if let s = session { req.setValue(s, forHTTPHeaderField: "X-LifeCall-Session") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw APIError(status: code, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: Auth

    /// Exchange an Apple identity token for a Worker session. Returns the session.
    static func authenticate(identityToken: String) async throws -> String {
        var req = URLRequest(url: URL(string: "\(Config.workerBaseURL)/v1/auth")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["identityToken": identityToken])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: "")
        }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = obj?["session"] as? String else { throw APIError(status: 500, body: "no session") }
        return token
    }

    // MARK: LLM (OpenRouter via Worker — OpenAI-compatible)

    /// Single-shot chat completion; returns the assistant message content.
    static func chat(system: String? = nil, user: String, jsonMode: Bool = false,
                     temperature: Double = 0.2) async throws -> String {
        var messages: [[String: Any]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": user])
        var body: [String: Any] = ["model": "default", "messages": messages, "temperature": temperature]
        if jsonMode { body["response_format"] = ["type": "json_object"] }
        let data = try await request("/v1/chat/completions", method: "POST", json: body)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((root?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
    }

    // MARK: Leads

    static func saveLead(_ lead: Lead) async throws {
        let data = try JSONEncoder().encode(lead)
        let obj = try JSONSerialization.jsonObject(with: data)
        _ = try await request("/v1/leads", method: "POST", json: obj)
    }

    static func fetchLeads() async throws -> [Lead] {
        let data = try await request("/v1/leads")
        return try JSONDecoder().decode([Lead].self, from: data)
    }

    // MARK: Documents (private R2 via Worker)

    /// Upload PDF data, returns the owner-scoped Worker URL that serves it.
    static func uploadDocument(_ pdf: Data, filename: String = "coverage-proposal.pdf") async throws -> String {
        var req = URLRequest(url: URL(string: "\(Config.workerBaseURL)/v1/documents")!)
        req.httpMethod = "POST"
        if let s = session { req.setValue(s, forHTTPHeaderField: "X-LifeCall-Session") }
        let boundary = "lifecall-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(pdf)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: "")
        }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["url"] as? String ?? ""
    }

    // MARK: Email

    static func sendEmail(to: String, subject: String, html: String) async throws {
        _ = try await request("/v1/email", method: "POST", json: ["to": to, "subject": subject, "html": html])
    }

    // MARK: Voice

    /// Fetch a short-lived ElevenLabs conversation token (the Worker mints it with
    /// the ElevenLabs API key — never on the device). For private agents.
    static func voiceToken() async throws -> String {
        let data = try await request("/v1/voice/token", method: "POST", json: ["agentId": Config.elevenLabsAgentId])
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = obj?["token"] as? String else { throw APIError(status: 500, body: "no token") }
        return token
    }

    // MARK: Outbound dial (consent-gated server-side)

    static func dial(to number: String) async throws {
        _ = try await request("/v1/dial", method: "POST", json: ["to": number])
    }
}
