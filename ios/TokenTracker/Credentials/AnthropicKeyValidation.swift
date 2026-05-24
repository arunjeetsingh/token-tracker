import Foundation

/// Lightweight format check for Anthropic admin API keys.
///
/// Anthropic admin keys start with `sk-ant-admin01-` and are followed by a
/// long opaque token of URL-safe characters. We do **not** try to be exact —
/// just enough to (a) reject obvious typos and (b) recognize a paste-from-
/// clipboard worth offering as a suggestion. Real validation happens when we
/// hit the API.
enum AnthropicKeyValidation {
    /// Loose prefix used by clipboard auto-detect. We accept either the admin
    /// prefix or the regular `sk-ant-` prefix; the API call itself will fail
    /// fast if a non-admin key was pasted, and we'll surface the error.
    static let clipboardPrefixes = ["sk-ant-admin01-", "sk-ant-api03-", "sk-ant-"]

    /// Minimum total length we'll even consider — keeps obvious garbage out.
    static let minLength = 32

    /// True if `candidate` looks plausibly like an Anthropic key — used to
    /// decide whether to surface the "Paste detected key?" affordance.
    static func looksLikeAnthropicKey(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minLength, trimmed.count <= 256 else { return false }
        guard clipboardPrefixes.contains(where: { trimmed.hasPrefix($0) }) else { return false }
        // Anthropic keys are URL-safe-ish: letters, digits, dashes, underscores.
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Best-effort masked rendering, e.g. `sk-ant-admin01-…XyZ9`.
    static func masked(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else { return "••••" }
        let prefix = trimmed.prefix(15)
        let suffix = trimmed.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}
