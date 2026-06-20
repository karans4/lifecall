import Foundation

/// Pulls a structured lead out of a call transcript. The LLM (OpenRouter) is
/// reached through the LifeCall Worker — no inference key on the device.
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

        let content = try await WorkerAPI.chat(user: prompt, jsonMode: true, temperature: 0.1)
        var lead = (try? JSONDecoder().decode(Lead.self, from: Data(content.utf8))) ?? Lead()
        lead.transcript = transcript
        return lead
    }
}
