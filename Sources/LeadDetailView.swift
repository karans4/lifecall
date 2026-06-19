import SwiftUI

/// Full dossier for a captured lead — conversation summary, the fact-find a
/// producer would take, contact info, the booked follow-up, and the transcript.
struct LeadDetailView: View {
    let lead: Lead
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerBlock

                    if let s = lead.summary, !s.isEmpty {
                        section("Call summary", icon: "text.quote") {
                            Text(s).foregroundStyle(.white.opacity(0.85)).font(.callout)
                        }
                    }

                    contactBlock

                    if let ff = lead.factFind, !factRows(ff).isEmpty {
                        section("Fact-find", icon: "magnifyingglass") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(factRows(ff), id: \.0) { row in
                                    factRow(row.0, row.1)
                                }
                            }
                        }
                    }

                    if let t = lead.transcript, !t.isEmpty {
                        section("Transcript", icon: "waveform") {
                            Text(t)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.white.opacity(0.7))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(20)
            }
            .background(
                LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.12),
                                        Color(red: 0.02, green: 0.02, blue: 0.05)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Blocks

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lead.name ?? "Unknown")
                .font(.title.bold())
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                pill(lead.outcome ?? "—", outcomeColor(lead.outcome))
                ForEach([lead.age.map { "Age \($0)" }, lead.coverageType, lead.coverageAmount, lead.monthlyBudget]
                    .compactMap { $0 }, id: \.self) { chip in
                    pill(chip, .blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contactBlock: some View {
        section("Contact & follow-up", icon: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 10) {
                if let e = lead.email, !e.isEmpty { factRow("Email", e) }
                if let p = lead.phone, !p.isEmpty { factRow("Phone", p) }
                if let cb = lead.callbackAt, !cb.isEmpty {
                    factRow("Callback", Self.prettyDate(cb), tint: .orange)
                }
                if (lead.email ?? "").isEmpty && (lead.phone ?? "").isEmpty && (lead.callbackAt ?? "").isEmpty {
                    Text("No contact details captured.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    // MARK: - Helpers

    private func factRows(_ ff: FactFind) -> [(String, String)] {
        [("Motive", ff.motive), ("Dependents", ff.dependents),
         ("Debt", ff.debt), ("Income", ff.income),
         ("Mortgage", ff.mortgage), ("Education", ff.education),
         ("Existing coverage", ff.existingCoverage), ("Tobacco", ff.tobacco),
         ("Health", ff.healthConditions), ("Height / weight", ff.heightWeight),
         ("Recommended", ff.recommendedProduct), ("Objections", ff.objections)]
            .compactMap { label, value in
                guard let v = value, !v.isEmpty, v.lowercased() != "null" else { return nil }
                return (label, v)
            }
    }

    private func section<Content: View>(_ title: String, icon: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(.cyan)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05)))
    }

    private func factRow(_ label: String, _ value: String, tint: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.callout)
                .foregroundStyle(tint == .white ? .white.opacity(0.9) : tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.22))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func outcomeColor(_ outcome: String?) -> Color {
        switch outcome {
        case "booked", "qualified": return .green
        case "callback":            return .orange
        case "not_interested":      return .red
        default:                    return .gray
        }
    }

    /// Render an ISO 8601 callback timestamp as a friendly local string.
    static func prettyDate(_ iso: String) -> String {
        let parsers: [ISO8601DateFormatter] = {
            let a = ISO8601DateFormatter()
            a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let b = ISO8601DateFormatter()
            b.formatOptions = [.withInternetDateTime]
            return [a, b]
        }()
        for p in parsers {
            if let date = p.date(from: iso) {
                let out = DateFormatter()
                out.dateFormat = "EEE MMM d, h:mm a"
                return out.string(from: date)
            }
        }
        return iso
    }
}
