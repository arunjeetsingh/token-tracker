import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: DashboardState = .idle

    /// True while a network refresh is in flight against a real Anthropic
    /// key. Independent of `state` so the dashboard can stay on `.loaded`
    /// (showing cached or last-fetched data) while the refresh button
    /// surfaces a progress indicator. Demo mode does not set this — the
    /// snapshot resolves synchronously.
    @Published private(set) var isRefreshing: Bool = false

    /// Last successfully-used key, kept in memory only so Settings can show a
    /// masked rendering without re-reading the Keychain. Reset on disconnect.
    @Published private(set) var maskedKey: String?

    /// Errors surfaced via the onboarding flow (e.g. auth failure on save).
    struct ConnectError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Dependencies

    private let cost: CostProviding
    private let keychain: CredentialStoring
    private let cache: ReportCaching

    /// Production callers use the zero-arg form, which wires up the live
    /// Anthropic API, Keychain, and `UserDefaults` cache. Tests inject mocks
    /// for each collaborator to exercise the state machine in isolation.
    init(
        cost: CostProviding = LiveCostProvider(),
        keychain: CredentialStoring = LiveCredentialStore(),
        cache: ReportCaching = LiveReportCache()
    ) {
        self.cost = cost
        self.keychain = keychain
        self.cache = cache
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
            guard let key = try keychain.load(), !key.isEmpty else {
                state = .needsCredentials
                return
            }
            maskedKey = AnthropicKeyValidation.masked(key)
            // Show cached data immediately so the user never stares at an
            // empty screen on launch. The refresh below will replace it
            // (or, on auth failure, the keychain wipe in refresh(using:)
            // will already have cleared the cache). On cache miss we still
            // fall through to .loading so the user sees the spinner — that
            // path is unchanged from before.
            if let cached = cache.load() {
                state = .loaded(report: cached.report, orgName: cached.orgName)
            }
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
        do {
            let identity = try await cost.whoami(apiKey: trimmed)
            // Real key authenticated successfully — user has explicitly chosen
            // to leave demo mode. Clear the persisted flag so the DEMO pill
            // disappears. (We do this only AFTER whoami succeeds; if the
            // network call fails, we preserve the previous demo state so a
            // transient failure doesn't strand a reviewer with no working UI.
            // 401/403 failures are handled in the catch branch below and
            // intentionally leave the flag alone.)
            DemoMode.isPersistedActive = false
            try keychain.save(trimmed)
            maskedKey = AnthropicKeyValidation.masked(trimmed)
            // Now fetch cost. A *transient* failure here keeps the saved key
            // (it auth'd) and surfaces in the dashboard state. But a 401/403
            // means the key was rejected after all (revoked, or insufficient
            // scope, between whoami and this call) — honor the documented
            // "401/403 → wipe key + re-onboard" contract instead of stranding a
            // dead key in the Keychain behind a generic dashboard error. Mirrors
            // the auth branch in refresh(using:).
            do {
                let report = try await cost.monthToDateCost(apiKey: trimmed)
                cache.save(report: report, orgName: identity.name)
                state = .loaded(report: report, orgName: identity.name)
            } catch let httpError as AnthropicHTTPError where httpError.status == 401 || httpError.status == 403 {
                try? keychain.delete()
                cache.clear()
                maskedKey = nil
                state = .needsCredentials
                return .failure(ConnectError(message: "Anthropic rejected this key. Double-check you copied an Admin key (starts with sk-ant-admin01-…) and try again."))
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
            guard let key = try keychain.load() else {
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
        // Drop the cached snapshot too so a fresh connection (potentially a
        // different Anthropic org) doesn't briefly flash the previous owner's
        // data while it loads.
        cache.clear()
        do {
            try keychain.delete()
        } catch {
            // We still flip back to onboarding — the user clearly wants out.
            state = .failed(message: "Disconnected, but Keychain reported: \(error.localizedDescription)")
            return
        }
        maskedKey = nil
        state = .needsCredentials
    }

    private func refresh(using key: String) async {
        // If we already have data on screen (cached snapshot from bootstrap,
        // or a previously-loaded report from a manual refresh), keep it
        // visible and just surface the refresh indicator in the toolbar.
        // Only fall back to the full-screen spinner when there's literally
        // nothing to show — first install, post-disconnect, or after an
        // error wiped the loaded state.
        let hasSomethingToShow = state.isLoaded
        if hasSomethingToShow {
            isRefreshing = true
        } else {
            state = .loading
        }
        defer { isRefreshing = false }

        do {
            async let identity = cost.whoami(apiKey: key)
            async let report = cost.monthToDateCost(apiKey: key)
            let (orgID, mtd) = try await (identity, report)
            maskedKey = AnthropicKeyValidation.masked(key)
            cache.save(report: mtd, orgName: orgID.name)
            state = .loaded(report: mtd, orgName: orgID.name)
        } catch let httpError as AnthropicHTTPError where httpError.status == 401 || httpError.status == 403 {
            // Token went bad — wipe it (and the cache) and force re-onboarding.
            try? keychain.delete()
            cache.clear()
            maskedKey = nil
            state = .needsCredentials
        } catch {
            // Network / transient failure: if we have cached data on screen,
            // leave it there. The user can see the staleness via the report's
            // `asOf` timestamp and the cleared refresh indicator. Only
            // surface .failed when there's nothing else to look at.
            if !hasSomethingToShow {
                state = .failed(message: error.localizedDescription)
            }
        }
    }
}
