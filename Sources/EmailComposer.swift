import Foundation

/// Uses Nebius to decide WHICH documents fit this specific call and to draft a
/// tailored follow-up email. Different situations → different docs and stages.
enum EmailComposer {
    struct Plan {
        var subject: String
        var message: String
        var documentIds: [String]
        var needsFollowupStage: Bool
        var followupNote: String
    }

    static func plan(lead: Lead, transcript: String) async throws -> Plan {
        let prompt = """
        You are the follow-up engine for a life-insurance agent named Jordan. Read the \
        call transcript and decide what to send this person. You have these documents:

        \(DocumentCatalog.prompt)

        Pick ONLY the documents that genuinely fit how THIS call went — a lead who \
        committed needs the application, e-sign, exam, and disclosures; a lead who said \
        "I need to think about it" needs the comparison guide and a value/nurture piece, \
        NOT an application; an older final-expense lead needs the buyer's guide. Don't \
        over-send. Decide if another follow-up stage (a second touch/call) is warranted.

        Respond with ONLY this JSON:
        {
          "subject": "email subject line",
          "message": "2-3 sentences in Jordan's warm, confident voice, specific to this call",
          "documents": ["ids","from","the","catalog"],
          "needs_followup_stage": true or false,
          "followup_note": "one line: what the next stage should be, or empty"
        }

        TRANSCRIPT:
        \(transcript)
        """

        let content = try await WorkerAPI.chat(user: prompt, jsonMode: true, temperature: 0.2)
        let j = (try? JSONSerialization.jsonObject(with: Data(content.utf8))) as? [String: Any] ?? [:]

        return Plan(
            subject: j["subject"] as? String ?? "Your LifeCall follow-up",
            message: j["message"] as? String ?? "Great talking with you — here are your next steps.",
            documentIds: j["documents"] as? [String] ?? ["welcome"],
            needsFollowupStage: j["needs_followup_stage"] as? Bool ?? false,
            followupNote: j["followup_note"] as? String ?? ""
        )
    }

    /// Build the HTML from the plan + chosen documents and send it. Generates a
    /// real, personalized proposal PDF, uploads it, and features the live link.
    static func composeAndSend(to address: String, lead: Lead, transcript: String) async throws -> Plan {
        let plan = try await self.plan(lead: lead, transcript: transcript)
        let docs = plan.documentIds.compactMap { DocumentCatalog.find($0) }

        // Generate + upload the personalized proposal PDF to private storage
        // (best-effort). The returned URL is owner-scoped and served by the Worker.
        let pdf = PDFGenerator.coverageProposal(for: lead)
        let proposalURL = try? await WorkerAPI.uploadDocument(pdf)

        let html = renderHTML(lead: lead, plan: plan, docs: docs, proposalURL: proposalURL)
        try await WorkerAPI.sendEmail(to: address, subject: plan.subject, html: html)
        return plan
    }

    /// A clean, branded HTML email. The proposal PDF is the real attachment; the
    /// Nebius-picked documents are listed as what's enclosed (no dead links).
    private static func renderHTML(lead: Lead, plan: Plan, docs: [SalesDocument], proposalURL: String?) -> String {
        let cta = proposalURL.map { url in
            """
            <div style="margin:26px 0;">
              <a href="\(url)" style="background:#2f73f2;color:#ffffff;text-decoration:none;
                 font-weight:600;font-size:15px;padding:14px 26px;border-radius:10px;display:inline-block;">
                 📄 View your personalized coverage proposal
              </a>
            </div>
            """
        } ?? ""

        let included = docs.isEmpty ? "" : """
        <p style="font-weight:600;margin-bottom:6px;">Also enclosed for you:</p>
        <ul style="margin-top:0;color:#333;">
          \(docs.map { "<li>\($0.title)</li>" }.joined())
        </ul>
        """

        return """
        <div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
                    max-width:560px;margin:0 auto;color:#1f2230;line-height:1.5;">
          <div style="background:linear-gradient(120deg,#0c1229,#2f73f2);color:#fff;
                      padding:22px 24px;border-radius:14px 14px 0 0;">
            <div style="font-size:20px;font-weight:700;">LifeCall</div>
            <div style="font-size:12px;opacity:0.8;letter-spacing:0.5px;">YOUR COVERAGE FOLLOW-UP</div>
          </div>
          <div style="border:1px solid #eee;border-top:none;border-radius:0 0 14px 14px;padding:24px;">
            <h2 style="margin:0 0 12px;font-size:18px;">Hi \(lead.name ?? "there"), it's Jordan from LifeCall</h2>
            <p>\(plan.message)</p>
            \(cta)
            \(included)
            <p style="margin-top:24px;">Talk soon,<br><b>Jordan</b><br>
               <span style="color:#888;font-size:13px;">Your LifeCall broker</span></p>
          </div>
        </div>
        """
    }
}
