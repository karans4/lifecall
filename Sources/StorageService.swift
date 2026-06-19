import Foundation

/// Uploads generated documents to a public Insforge storage bucket and returns
/// a durable public URL (the API path re-signs a CDN link on each fetch).
enum StorageService {
    static let bucket = "documents"

    /// Upload `data` under `key` (e.g. "leads/<id>/proposal.pdf"). Returns the
    /// public URL an email recipient can open.
    static func upload(_ data: Data, key: String, contentType: String) async throws -> String {
        let endpoint = "\(Config.insforgeBaseURL)/api/storage/buckets/\(bucket)/objects/\(key)"
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(Config.insforgeKey)", forHTTPHeaderField: "Authorization")

        let boundary = "lifecall-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let filename = (key as NSString).lastPathComponent
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Storage", code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return endpoint
    }
}
