import SwiftUI

@main
struct LifeCallApp: App {
    @StateObject private var auth = AuthStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(auth)
            .onChange(of: scenePhase) { phase in
                if phase == .active { Task { await auth.refreshCredentialState() } }
            }
        }
    }
}
