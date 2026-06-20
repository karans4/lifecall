import AuthenticationServices
import SwiftUI

/// Client-side Sign in with Apple, adapted from the halo app's AuthStore.
/// The stable Apple user identifier *is* the identity — kept in the Keychain
/// (durable across reinstalls within the same Apple ID + team). Name/email are
/// cached the first time Apple hands them over (it only does so once).
///
/// NOTE: this is identity + a client-side gate. It is NOT a substitute for
/// server-side verification of the Apple identity token — that comes with the
/// backend tier (see SECURITY_REVIEW). Until then, treat auth as a soft gate.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var userID: String?
    @Published private(set) var displayName: String?
    @Published private(set) var email: String?
    @Published var lastError: String?

    private let keychainAccount = "apple-user-id"
    private let defaults = UserDefaults.standard

    var isSignedIn: Bool { userID != nil }

    init() {
        userID = Keychain.read(account: keychainAccount)
        displayName = defaults.string(forKey: "auth.displayName")
        email = defaults.string(forKey: "auth.email")
    }

    /// Apple only returns fullName/email on first sign-up; later authorizations
    /// carry just the user identifier. Cache the rich fields once; never clobber
    /// them with later nils.
    func adopt(_ credential: ASAuthorizationAppleIDCredential) {
        let id = credential.user
        Keychain.save(account: keychainAccount, value: id)
        userID = id

        // Exchange the Apple identity token (signed JWT, only present on a fresh
        // authorization) for a LifeCall Worker session token.
        if let data = credential.identityToken,
           let jwt = String(data: data, encoding: .utf8), !jwt.isEmpty {
            Task {
                do { WorkerAPI.session = try await WorkerAPI.authenticate(identityToken: jwt) }
                catch { self.lastError = "Sign-in to LifeCall failed: \(error)" }
            }
        }

        if let name = credential.fullName,
           let formatted = PersonNameComponentsFormatter().string(for: name)
            .flatMap({ $0.isEmpty ? nil : $0 }) {
            displayName = formatted
            defaults.set(formatted, forKey: "auth.displayName")
        }
        if let mail = credential.email, !mail.isEmpty {
            email = mail
            defaults.set(mail, forKey: "auth.email")
        }
        lastError = nil
    }

    func signOut() {
        Keychain.delete(account: keychainAccount)
        defaults.removeObject(forKey: "auth.displayName")
        defaults.removeObject(forKey: "auth.email")
        defaults.removeObject(forKey: "auth.session")
        userID = nil
        displayName = nil
        email = nil
    }

    /// On every foreground, ask Apple whether the credential is still valid.
    /// If the user revoked LifeCall from their Apple ID settings, sign them out.
    func refreshCredentialState() async {
        guard let id = userID else { return }
        let provider = ASAuthorizationAppleIDProvider()
        let state = try? await provider.credentialState(forUserID: id)
        switch state {
        case .revoked, .notFound:
            signOut()
        default:
            break
        }
    }
}

/// Minimal Keychain string store for a single durable identifier.
enum Keychain {
    private static let service = "ai.halo.lifecall.auth"

    static func save(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
