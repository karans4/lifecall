import SwiftUI

/// Buy prepaid call hours. Volume pricing — $/hr drops with bigger packs.
/// Checkout happens on the web (Stripe), so Apple takes nothing.
struct BillingView: View {
    @State private var packs: [WorkerAPI.Pack] = []
    @State private var loadingPack: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.12),
                                        Color(red: 0.02, green: 0.02, blue: 0.05)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Text("Buy call hours")
                            .font(.title.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Pay per hour of talk time. Bigger packs, lower rate.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(packs) { p in
                            Button { buy(p) } label: { packRow(p) }
                                .buttonStyle(.plain)
                                .disabled(loadingPack != nil)
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { packs = (try? await WorkerAPI.packs()) ?? [] }
        }
        .preferredColorScheme(.dark)
    }

    private func packRow(_ p: WorkerAPI.Pack) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(p.hours) hours").font(.headline).foregroundStyle(.white)
                Text(String(format: "$%.2f/hr", Double(p.per_hour_cents) / 100))
                    .font(.caption).foregroundStyle(.cyan)
            }
            Spacer()
            if loadingPack == p.id {
                ProgressView().tint(.white)
            } else {
                Text(String(format: "$%.0f", Double(p.price_cents) / 100))
                    .font(.title3.bold()).foregroundStyle(.white)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
    }

    private func buy(_ p: WorkerAPI.Pack) {
        loadingPack = p.id
        Task {
            defer { loadingPack = nil }
            if let s = try? await WorkerAPI.checkoutURL(packId: p.id), let u = URL(string: s) {
                openURL(u)
                dismiss()
            }
        }
    }
}
