import SwiftUI

/// Buy prepaid call hours. Volume pricing — $/hr drops with bigger packs.
/// Checkout runs in an in-app webview (Stripe), so Apple takes nothing and the
/// flow never leaves the app.
struct BillingView: View {
    /// Set true when a Checkout completed, so the parent can start polling the balance.
    @Binding var didPurchase: Bool

    @State private var packs: [WorkerAPI.Pack] = []
    @State private var loadingPack: String?
    @State private var checkoutURL: URL?
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
            .sheet(item: $checkoutURL) { u in
                CheckoutWebView(url: u) { success in
                    checkoutURL = nil
                    if success { didPurchase = true; dismiss() }
                }
            }
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
                checkoutURL = u
            }
        }
    }
}

// Allow presenting a sheet keyed on the checkout URL.
extension URL: Identifiable { public var id: String { absoluteString } }
