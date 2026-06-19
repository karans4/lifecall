import Foundation

/// Drop your keys here. Public key is safe to ship in-app (Vapi client SDK).
/// Private key is used for server-side outbound dialing — for the hackathon
/// demo we call it straight from the app; in production this lives on a server.
enum Config {
    // Vapi → Dashboard → API Keys. Public key ships in the client (safe);
    // the private key is read from the gitignored Secrets.swift.
    static let vapiPublicKey  = "f6e4ee8a-3ccb-4c91-806d-088de0c4f87a"
    static let vapiPrivateKey = Secrets.vapiPrivateKey

    // Vapi → Phone Numbers → the number id you'll dial *from* (+1 414 409 1562)
    static let vapiPhoneNumberId = "8b5b48d2-fcf6-48f0-8a5a-67287232c0ae"

    // Created once at launch from IntakeScript, or paste an existing assistant id.
    static var assistantId: String? = nil

    // Insforge (backend) — admin key from gitignored Secrets.swift.
    static let insforgeBaseURL = "https://ie3u75y4.us-east.insforge.app"
    static let insforgeKey      = Secrets.insforgeKey

    // Nebius (also used to extract a structured lead from the call transcript).
    static let nebiusBaseURL = "https://api.studio.nebius.com/v1"
    static let nebiusKey     = Secrets.nebiusKey
    static let nebiusModel   = "meta-llama/Llama-3.3-70B-Instruct"

    // Only your own test line is baked in. Anyone else you call, you dial yourself
    // via the "Call this number" field — that's the in-person consent.
    static let callbackAllowlist: Set<String> = [
        "+15555550100",  // your own test line
        "+15555550101",  // teammate
        "+15555550102",  // teammate
    ]
}
