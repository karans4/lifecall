import Foundation

/// A Playbook is the whole pipeline-as-config: it parameterizes the agent's
/// script, what to collect, how to score urgency (and what that triggers), which
/// documents to route, and how to book meetings. Life insurance ships as the
/// default; a new vertical is a new Playbook with no code change.
///
/// The app edits Playbooks and syncs them to the Worker, which uses them to drive
/// the live call (system prompt), extraction, urgency scoring, document routing,
/// auto-actions, and calendar booking.
struct Playbook: Codable, Identifiable {
    var id: String
    var name: String                 // "Life Insurance"
    var disclosure: String           // AI-disclosure opener
    var personaAndFlow: String       // the script body → system prompt
    var collect: [CollectField]      // the "things to get"
    var urgencyTiers: [UrgencyTier]  // Hot / Warm / Cold + what each triggers
    var documents: [PlaybookDocument]
    var calendar: CalendarConfig

    /// Whether ANY auto-action may fire for this playbook. Master safety switch —
    /// off by default; auto-dial additionally requires server-side consent.
    var autoActionsEnabled: Bool

    /// The full system prompt handed to the LLM, generated from the playbook.
    /// Fields are ordered by collection urgency so the agent chases the must-gets first.
    var systemPrompt: String {
        let fields = collect
            .sorted { $0.priority.rank < $1.priority.rank }
            .map { "- \($0.key): \($0.prompt) — \($0.priority.instruction)" }
            .joined(separator: "\n")
        return """
        \(personaAndFlow)

        DISCLOSE YOU'RE AN AI up front: \(disclosure)

        THINGS TO GET on this call (weave them in naturally, don't interrogate):
        \(fields)

        Always book the next step before hanging up, and confirm contact details by
        reading them back. End your turn with the word "goodbye" to close cleanly.
        """
    }

    var firstMessage: String { disclosure }
}

/// A field the agent should collect, and how it maps into the lead record.
struct CollectField: Codable, Identifiable {
    var id: String { key }
    var key: String              // e.g. "monthly_budget"
    var prompt: String           // instruction for the agent + extractor
    var priority: CollectPriority

    /// A critical field that's missing flags the call as incomplete.
    var required: Bool { priority == .critical }
}

/// How hard the agent should push to collect a field, and how the pipeline treats
/// it if it's missing after the call.
enum CollectPriority: String, Codable, CaseIterable {
    case critical    // must land it; don't end the call without it
    case high        // chase it; only skip if they clearly won't say
    case normal      // get it if it fits naturally
    case optional    // bonus

    var rank: Int { [.critical, .high, .normal, .optional].firstIndex(of: self) ?? 9 }

    var instruction: String {
        switch self {
        case .critical: return "MUST get this — don't wrap the call without it"
        case .high:     return "important, chase it"
        case .normal:   return "get it if it comes up naturally"
        case .optional: return "nice to have"
        }
    }
}

/// Urgency tier with the action it triggers. `autoDial`/`autoBook` only fire when
/// the playbook's autoActionsEnabled is true (and dialing also needs consent).
struct UrgencyTier: Codable, Identifiable {
    var id: String { name }
    var name: String          // "Hot" / "Warm" / "Cold"
    var criteria: String      // natural-language rule the scorer applies
    var color: String         // ui hint: "green"/"orange"/"gray"
    var action: AutoAction
}

enum AutoAction: String, Codable, CaseIterable {
    case none            // sort + flag only
    case sendDocuments   // auto-send the routed documents
    case autoBook        // auto-create the calendar meeting
    case autoDial        // auto-place an outbound call (consent-gated server-side)
}

/// A document template + when to send it. Supports PDF (generated) or DOCX.
struct PlaybookDocument: Codable, Identifiable {
    var id: String
    var title: String
    var kind: Kind
    var whenToUse: String           // routing instruction for the LLM
    var forOutcomes: [String]       // e.g. ["booked","qualified"]
    var forUrgency: [String]        // e.g. ["Hot"]

    enum Kind: String, Codable { case pdf, docx }
}

/// Calendar behavior for booked meetings.
struct CalendarConfig: Codable {
    var enabled: Bool
    var googleCalendar: Bool        // create a real Google Calendar event (OAuth)
    var icsInvite: Bool             // also attach an .ics invite to the email
    var meetingTitle: String        // template, e.g. "LifeCall: {name} — coverage review"
    var durationMinutes: Int
}

// MARK: - Default: Life Insurance

extension Playbook {
    static let lifeInsurance = Playbook(
        id: "life-insurance",
        name: "Life Insurance",
        disclosure: "Hey, this is Jordan — I'm an AI assistant with the brokerage, "
            + "following up on the coverage info you requested. A licensed agent reviews "
            + "everything I set up. You got a quick minute?",
        personaAndFlow: IntakeScript.systemPrompt,
        collect: [
            .init(key: "name", prompt: "their full name", priority: .critical),
            .init(key: "email", prompt: "best email for paperwork (read it back)", priority: .critical),
            .init(key: "phone", prompt: "best callback number in E.164", priority: .critical),
            .init(key: "age", prompt: "their age / date of birth", priority: .high),
            .init(key: "monthly_budget", prompt: "the final agreed monthly premium", priority: .high),
            .init(key: "callback_at", prompt: "a concrete follow-up time", priority: .high),
            .init(key: "coverage_amount", prompt: "desired face amount", priority: .normal),
            .init(key: "coverage_type", prompt: "product fit: term/whole/UL/IUL/final expense", priority: .normal),
        ],
        urgencyTiers: [
            .init(name: "Hot", criteria: "agreed to a premium and gave payment intent or said yes to applying",
                  color: "green", action: .sendDocuments),
            .init(name: "Warm", criteria: "qualified and interested but wants to think or compare; gave a callback time",
                  color: "orange", action: .sendDocuments),
            .init(name: "Cold", criteria: "not interested, unqualified, or no real engagement",
                  color: "gray", action: .none),
        ],
        documents: [
            .init(id: "application", title: "Application & e-Signature", kind: .pdf,
                  whenToUse: "lead committed/booked", forOutcomes: ["booked", "qualified"], forUrgency: ["Hot"]),
            .init(id: "proposal", title: "Personalized Coverage Proposal", kind: .pdf,
                  whenToUse: "always for an engaged lead", forOutcomes: ["booked", "qualified", "callback"], forUrgency: ["Hot", "Warm"]),
            .init(id: "comparison", title: "Term vs Whole vs IUL — Plain-English Guide", kind: .docx,
                  whenToUse: "lead undecided on product", forOutcomes: ["callback", "qualified"], forUrgency: ["Warm"]),
            .init(id: "cost_of_waiting", title: "The Real Cost of Waiting", kind: .docx,
                  whenToUse: "hesitant / nurture", forOutcomes: ["callback"], forUrgency: ["Warm"]),
        ],
        calendar: CalendarConfig(
            enabled: true, googleCalendar: true, icsInvite: true,
            meetingTitle: "LifeCall: {name} — coverage review", durationMinutes: 20
        ),
        autoActionsEnabled: false   // master switch off; auto-dial also needs consent
    )
}
