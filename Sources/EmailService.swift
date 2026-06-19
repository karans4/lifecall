import Foundation

/// Sends email via Insforge custom email (paid plan).
enum EmailService {
    static func send(to address: String, subject: String, html: String) async throws {
        var req = URLRequest(url: URL(string: "\(Config.insforgeBaseURL)/api/email/send-raw")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(Config.insforgeKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "to": address, "subject": subject, "html": html
        ])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Email", code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}
