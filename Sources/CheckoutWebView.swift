import SwiftUI
import WebKit

/// In-app Stripe Checkout. Loads the Checkout URL in a WKWebView and reports back
/// when it reaches the Worker's success page (or the user cancels) — so the flow
/// never leaves the app and closes itself on completion.
struct CheckoutWebView: View {
    let url: URL
    /// Called with `true` if Checkout completed (hit /billing/success), else `false`.
    let onFinish: (Bool) -> Void

    var body: some View {
        NavigationStack {
            WebView(url: url) { success in onFinish(success) }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Checkout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onFinish(false) }
                    }
                }
        }
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onFinish: (Bool) -> Void
        private var done = false
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // The Worker's success page marks a completed Checkout.
            if let u = navigationAction.request.url?.absoluteString, u.contains("/billing/success") {
                decisionHandler(.cancel)
                if !done { done = true; onFinish(true) }
                return
            }
            decisionHandler(.allow)
        }
    }
}
