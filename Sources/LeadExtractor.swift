import Foundation

/// Uses Nebius (Llama-3.3-70B) to pull a structured lead out of a call transcript.
enum LeadExtractor {
    static func extract(from transcript: String) async throws -> Lead {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let prompt = """
        From this life-insurance sales call transcript, extract a JSON object with \
        keys: name (string), age (number or null), coverage_type (term/whole/universal/iul/final_expense or null), \
        coverage_amount (string like "$250k" or null), \
        monthly_budget (string like "$45/mo" — the FINAL agreed monthly premium they'll \
        actually pay if one was settled on, NOT their budget ceiling; else null), \
        email (string or null, if they gave one), \
        phone (string in E.164 like +14155550123 if they gave a callback number, else null), \
        callback_at (if they agreed to a follow-up at a relative time like "in an hour" or \
        "tomorrow at 2", compute the absolute ISO 8601 timestamp relative to NOW=\(nowISO); else null), \
        outcome (one of: qualified, booked, not_interested, callback, unknown), \
        summary (2-3 sentence plain-English recap of how the call went and where it landed), \
        fact_find (an object capturing the discovery — use null for anything not covered — with keys: \
        motive, dependents, debt, income, mortgage, education, existing_coverage, tobacco, \
        health_conditions, height_weight, recommended_product, objections; each a short string or null). \
        Respond with ONLY the JSON object, no prose.

        TRANSCRIPT:
        \(transcript)
        """

        var req = URLRequest(url: URL(string: "\(Config.nebiusBaseURL)/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(Config.nebiusKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": Config.nebiusModel,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.1,
            "response_format": ["type": "json_object"]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        // Dig the model's content string out of the OpenAI-shaped response.
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = ((root?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String ?? "{}"

        var lead = (try? JSONDecoder().decode(Lead.self, from: Data(content.utf8))) ?? Lead()
        lead.transcript = transcript
        return lead
    }
}
