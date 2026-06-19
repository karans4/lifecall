import SwiftUI

/// Upcoming scheduled callbacks — every lead with a future `callback_at`,
/// grouped by day so you can see what's coming.
struct ScheduleView: View {
    let leads: [Lead]
    let onSelect: (Lead) -> Void

    /// A lead paired with its parsed callback date.
    private struct Appointment: Identifiable {
        let lead: Lead
        let date: Date
        var id: String { (lead.id ?? "") + date.description }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.12),
                                    Color(red: 0.02, green: 0.02, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Schedule")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Upcoming callbacks Jordan booked")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 8)

                    if grouped.isEmpty {
                        emptyState
                    } else {
                        ForEach(grouped, id: \.0) { day, appts in
                            dayGroup(day: day, appts: appts)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Pieces

    private func dayGroup(day: String, appts: [Appointment]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.cyan)
            ForEach(appts) { appt in
                Button { onSelect(appt.lead) } label: { row(appt) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func row(_ appt: Appointment) -> some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(Self.timeFmt.string(from: appt.date))
                    .font(.callout.bold().monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 76)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.cyan.opacity(0.15)))

            VStack(alignment: .leading, spacing: 3) {
                Text(appt.lead.name ?? "Unknown lead")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(subtitle(appt.lead))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if let p = appt.lead.phone, !p.isEmpty {
                Image(systemName: "phone.fill").foregroundStyle(.green.opacity(0.7)).font(.caption)
            }
            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.3)).font(.caption)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.25))
            Text("No callbacks scheduled")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            Text("When Jordan books a follow-up time on a call, it shows up here.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func subtitle(_ l: Lead) -> String {
        [l.coverageAmount, l.monthlyBudget, l.outcome]
            .compactMap { $0 }.joined(separator: " • ")
    }

    // MARK: - Data

    /// Future callbacks, grouped by day label, each day sorted by time.
    private var grouped: [(String, [Appointment])] {
        let now = Date()
        let appts = leads.compactMap { lead -> Appointment? in
            guard let iso = lead.callbackAt, let date = Self.parse(iso), date > now else { return nil }
            return Appointment(lead: lead, date: date)
        }.sorted { $0.date < $1.date }

        var order: [String] = []
        var buckets: [String: [Appointment]] = [:]
        for appt in appts {
            let key = Self.dayLabel(appt.date)
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]?.append(appt)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    // MARK: - Date helpers

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    private static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    static func parse(_ iso: String) -> Date? {
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = a.date(from: iso) { return d }
        let b = ISO8601DateFormatter()
        b.formatOptions = [.withInternetDateTime]
        return b.date(from: iso)
    }
}
