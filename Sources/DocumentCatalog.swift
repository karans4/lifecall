import Foundation

/// The materials a real life-insurance agent has on hand to send after a call.
/// Nebius picks the situation-appropriate subset per lead.
struct SalesDocument: Identifiable {
    let id: String
    let title: String
    let whenToUse: String
    let link: String   // stand-in links for the demo
}

enum DocumentCatalog {
    static let all: [SalesDocument] = [
        .init(id: "welcome",       title: "Welcome & Next Steps",
              whenToUse: "Always — friendly recap and what happens next.",
              link: "https://lifecall.app/docs/welcome"),
        .init(id: "comparison",    title: "Term vs. Whole vs. IUL — Plain-English Guide",
              whenToUse: "Lead is undecided on product type or asked about differences.",
              link: "https://lifecall.app/docs/product-comparison"),
        .init(id: "needs_worksheet", title: "Coverage Needs Worksheet (DIME)",
              whenToUse: "Lead unsure how much coverage they need.",
              link: "https://lifecall.app/docs/needs-worksheet"),
        .init(id: "illustration", title: "Sample Policy Illustration",
              whenToUse: "Lead is interested and wants to see numbers/premiums.",
              link: "https://lifecall.app/docs/illustration"),
        .init(id: "application",  title: "Application & e-Signature",
              whenToUse: "Lead committed/booked — ready to apply.",
              link: "https://lifecall.app/apply"),
        .init(id: "exam",         title: "Schedule Your Free Medical Exam / Tele-Interview",
              whenToUse: "Lead applying for a fully-underwritten policy.",
              link: "https://lifecall.app/schedule-exam"),
        .init(id: "final_expense", title: "Final Expense Buyer's Guide",
              whenToUse: "Older lead or final-expense / burial coverage discussed.",
              link: "https://lifecall.app/docs/final-expense"),
        .init(id: "work_coverage", title: "Why Work Coverage Isn't Enough",
              whenToUse: "Lead said they already have coverage through their employer.",
              link: "https://lifecall.app/docs/work-coverage"),
        .init(id: "objection_value", title: "The Real Cost of Waiting",
              whenToUse: "Lead hesitant on price or wants to think it over — nurture.",
              link: "https://lifecall.app/docs/cost-of-waiting"),
        .init(id: "buyers_guide", title: "State Buyer's Guide & Disclosures",
              whenToUse: "Lead is applying — required disclosure.",
              link: "https://lifecall.app/docs/buyers-guide"),
    ]

    /// Compact catalog for the LLM to choose from.
    static var prompt: String {
        all.map { "- \($0.id): \($0.title) — \($0.whenToUse)" }.joined(separator: "\n")
    }

    static func find(_ id: String) -> SalesDocument? { all.first { $0.id == id } }
}
