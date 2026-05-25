import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: DashboardState = .idle

    /// Last successfully-used key, kept in memory only so Settings can show a
    /// masked rendering without re-reading the Keychain. Reset on disconnect.
    @Published private(set) var maskedKey: String?

    /// Errors surfaced via the onboarding flow (e.g. auth failure on save).
    struct ConnectError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func bootstrap() async {
        do {
            guard let key = try KeychainStore.load(.anthropicAdminKey), !key.isEmpty else {
                state = .needsCredentials
                return
            }
            maskedKey = AnthropicKeyValidation.masked(key)
            await refresh(using: key)
        } catch {
            state = .failed(message: "Keychain error: \(error.localizedDescription)")
        }
    }

    /// Used by the onboarding view. Verifies the key against the API *before*
    /// committing to the Keychain so we don't store junk that we'll then have
    /// to surface as a generic failure on the next launch.
    func connect(using rawKey: String) async -> Result<Void, Error> {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ConnectError(message: "Paste your admin key to continue."))
        }
        state = .loading
        let client = AnthropicClient(apiKey: trimmed)
        do {
            let identity = try await client.whoami()
            try KeychainStore.save(trimmed, for: .anthropicAdminKey)
            maskedKey = AnthropicKeyValidation.masked(trimmed)
            // Now fetch cost. If this fails the key is still saved (it auth'd) —
            // we surface the error in the dashboard state, not back to onboarding.
            do {
                let report = try await client.monthToDateCost()
                state = .loaded(report: report, orgName: identity.name)
            } catch {
                state = .failed(message: error.localizedDescription)
            }
            return .success(())
        } catch let httpError as AnthropicHTTPError where httpError.status == 401 || httpError.status == 403 {
            state = .needsCredentials
            return .failure(ConnectError(message: "Anthropic rejected this key. Double-check you copied an Admin key (starts with sk-ant-admin01-…) and try again."))
        } catch {
            state = .needsCredentials
            return .failure(ConnectError(message: error.localizedDescription))
        }
    }

    func refresh() async {
        do {
            guard let key = try KeychainStore.load(.anthropicAdminKey) else {
                state = .needsCredentials
                maskedKey = nil
                return
            }
            await refresh(using: key)
        } catch {
            state = .failed(message: "Keychain error: \(error.localizedDescription)")
        }
    }

    func disconnect() async {
        do {
            try KeychainStore.delete(.anthropicAdminKey)
        } catch {
            // We still flip back to onboarding — the user clearly wants out.
            state = .failed(message: "Disconnected, but Keychain reported: \(error.localizedDescription)")
            return
        }
        maskedKey = nil
        state = .needsCredentials
    }

    private func refresh(using key: String) async {
        state = .loading
        let client = AnthropicClient(apiKey: key)
        do {
            async let identity = client.whoami()
            async let report = client.monthToDateCost()
            let (orgID, mtd) = try await (identity, report)
            maskedKey = AnthropicKeyValidation.masked(key)
            state = .loaded(report: mtd, orgName: orgID.name)
        } catch let httpError as AnthropicHTTPError where httpError.status == 401 || httpError.status == 403 {
            // Token went bad — wipe it and force re-onboarding.
            try? KeychainStore.delete(.anthropicAdminKey)
            maskedKey = nil
            state = .needsCredentials
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}
