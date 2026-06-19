import Foundation

/// Stores and fetches leads from Insforge (PostgREST-style REST API).
enum InsforgeService {
    private static var recordsURL: URL {
        URL(string: "\(Config.insforgeBaseURL)/api/database/records/leads")!
    }

    /// Saves a lead. Insforge expects an array of row objects.
    static func save(_ lead: Lead) async throws {
        var req = URLRequest(url: recordsURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(Config.insforgeKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode([lead])
        let (_, resp) = try await URLSession.shared.data(for: req)
        try check(resp)
    }

    /// Newest leads first.
    static func fetch(limit: Int = 25) async throws -> [Lead] {
        var comps = URLComponents(url: recordsURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "order", value: "created_at.desc"),
            .init(name: "limit", value: "\(limit)")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(Config.insforgeKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp)
        return try JSONDecoder().decode([Lead].self, from: data)
    }

    /// Patch a single lead by id.
    static func update(id: String, fields: [String: Any]) async throws {
        var comps = URLComponents(url: recordsURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "id", value: "eq.\(id)")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(Config.insforgeKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (_, resp) = try await URLSession.shared.data(for: req)
        try check(resp)
    }

    private static func check(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Insforge", code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}
