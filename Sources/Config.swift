import Foundation

/// The app holds NO provider keys anymore. Everything sensitive (OpenRouter,
/// ElevenLabs, Resend, the database) lives behind the LifeCall Worker, which the
/// app reaches with a Sign in with Apple session token. The only config here is
/// public: where the Worker lives and which ElevenLabs agent to talk to.
enum Config {
    /// The Cloudflare Worker base URL (see worker/). Override per environment.
    static let workerBaseURL = "https://lifecall.<your-account>.workers.dev"

    /// ElevenLabs Conversational AI agent id (not a secret; the signed URL that
    /// authorizes a session is fetched from the Worker).
    static let elevenLabsAgentId = "REPLACE_WITH_AGENT_ID"
}
