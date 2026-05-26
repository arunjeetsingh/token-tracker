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
        // Demo Mode: skip Keychain + API entirely. Triggered by either
        //   (a) launch arg `-DemoMode YES` / `-DemoModeScreen ...` (screenshot capture), or
        //   (b) a reviewer pasting `DemoMode.appReviewKey` in onboarding (persisted).
        if DemoMode.isEnabled {
            switch DemoMode.screen ?? .dashboard {
            case .dashboard:
                let demo = DemoMode.snapshot()
                // Render the masked form of the actual magic key so Settings
                // looks consistent (`sk-…w22`). Falls back to the same
                // masking path real keys use.
                maskedKey = AnthropicKeyValidation.masked(DemoMode.appReviewKey)
                state = .loaded(report: demo.report, orgName: demo.orgName)
            case .onboarding:
                // Force the onboarding flow without touching Keychain.
                maskedKey = nil
                state = .needsCredentials
            }
            return
        }
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
        // App Reviewer demo magic key: short-circuit before any network call
        // or Keychain write. Persist the flag so demo mode survives relaunch.
        if DemoMode.isReviewKey(trimmed) {
            DemoMode.isPersistedActive = true
            let demo = DemoMode.snapshot()
            maskedKey = AnthropicKeyValidation.masked(trimmed)
            state = .loaded(report: demo.report, orgName: demo.orgName)
            return .success(())
        }
        state = .loading
        let client = AnthropicClient(apiKey: trimmed)
        do {
            let identity = try await client.whoami()
            // Real key authenticated successfully — user has explicitly chosen
            // to leave demo mode. Clear the persisted flag so the DEMO pill
            // disappears. (We do this only AFTER whoami succeeds; if the
            // network call fails, we preserve the previous demo state so a
            // transient failure doesn't strand a reviewer with no working UI.
            // 401/403 failures are handled in the catch branch below and
            // intentionally leave the flag alone.)
            DemoMode.isPersistedActive = false
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
        // Demo mode never wrote to Keychain — if we try to read the key
        // here we'd get nil and bounce the user back to onboarding. Mirror
        // the bootstrap() short-circuit and just re-render the canned data.
        if DemoMode.isEnabled {
            let demo = DemoMode.snapshot()
            maskedKey = AnthropicKeyValidation.masked(DemoMode.appReviewKey)
            state = .loaded(report: demo.report, orgName: demo.orgName)
            return
        }
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
        // Demo mode never wrote to Keychain; clearing the persisted flag is
        // the only state change needed. We still call delete below in case
        // the user toggled between real and demo over the lifetime of the
        // install — it's a no-op when nothing's stored.
        DemoMode.isPersistedActive = false
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
