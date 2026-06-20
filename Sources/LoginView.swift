import AuthenticationServices
import SwiftUI

/// The gate — one surface, one button: Sign in with Apple. No passwords, no
/// account server. Themed to match LifeCall's dark UI.
struct LoginView: View {
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.12),
                                    Color(red: 0.02, green: 0.02, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .blue],
                                                    startPoint: .top, endPoint: .bottom))
                Text("LifeCall")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 18)
                Text("Your AI life-insurance closer.\nSign in to get started.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 10)
                Spacer()

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        if let credential = authorization.credential
                            as? ASAuthorizationAppleIDCredential {
                            auth.adopt(credential)
                        }
                    case .failure(let error):
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            auth.lastError = error.localizedDescription
                        }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(Capsule())
                .padding(.horizontal, 32)

                if let err = auth.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(.top, 10)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer().frame(height: 44)
            }
        }
        .preferredColorScheme(.dark)
    }
}
