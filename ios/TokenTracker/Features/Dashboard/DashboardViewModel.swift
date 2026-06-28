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

    /// Last successfully-used key(s), kept in memory only so Settings can show a
    /// masked rendering without re-reading the Keychain. Reset on disconnect.
    @Published private(set) var maskedKey: String?

    /// Per-provider reports backing the combined dashboard and provider filter.
    @Published private(set) var providerReports: [ProviderReport] = []

    /// nil means “All providers”; otherwise the dashboard shows one provider.
    @Published private(set) var selectedProvider: ProviderKind?

    /// User's on-device monthly spend-limit target in cents (nil = unset).
    /// Local tracking value only — the Admin API can't read/set the real limit.
    @Published private(set) var spendLimitCents: Int64?

    /// Whether the user opted into the "90% of limit" spend alert.
    @Published private(set) var spendAlertEnabled: Bool

    /// Errors surfaced via the onboarding flow (e.g. auth failure on save).
    struct ConnectError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Dependencies

    private let cost: CostProviding
    private let keychain: CredentialStoring
    private let cache: ReportCaching
    private var spendLimits: SpendLimitStoring
    private var notificationPrefs: NotificationPreferenceStoring

    /// Production callers use the zero-arg form, which wires up the live
    /// Anthropic API, Keychain, and `UserDefaults` stores. Tests inject mocks
    /// for each collaborator to exercise the state machine in isolation.
    init(
        cost: CostProviding = LiveCostProvider(),
        keychain: CredentialStoring = LiveCredentialStore(),
        cache: ReportCaching = LiveReportCache(),
        spendLimits: SpendLimitStoring = LiveSpendLimitStore(),
        notificationPrefs: NotificationPreferenceStoring = LiveNotificationPrefs()
    ) {
        self.cost = cost
        self.keychain = keychain
        self.cache = cache
        self.spendLimits = spendLimits
        self.notificationPrefs = notificationPrefs
        self.spendLimitCents = spendLimits.limitCents
        self.spendAlertEnabled = notificationPrefs.alertEnabled
    }

    /// Persist (or clear, when nil) the local spend-limit target. Clearing the
    /// limit also turns off the 90% alert — there's nothing to compare against,
    /// so leaving it on would strand a scheduled background check and a
    /// disabled-but-on switch in Settings. The view layer reacts to
    /// `spendAlertEnabled` flipping to cancel the scheduled task.
    func setSpendLimit(_ cents: Int64?) {
        spendLimits.limitCents = cents
        spendLimitCents = cents
        if cents == nil, spendAlertEnabled {
            setSpendAlertEnabled(false)
        }
    }

    /// Persist the spend-alert opt-in. The view layer requests notification
    /// permission (and schedules the background check) before calling this with
    /// `true`.
    func setSpendAlertEnabled(_ enabled: Bool) {
        notificationPrefs.alertEnabled = enabled
        spendAlertEnabled = enabled
    }

    func bootstrap() async {
        // Demo Mode: skip Keychain + API entirely. Triggered by either
        //   (a) launch arg `-DemoMode YES` / `-DemoModeScreen ...` (screenshot capture), or
        //   (b) a reviewer pasting `DemoMode.appReviewKey` in onboarding (persisted).
        if DemoMode.isEnabled {
            switch DemoMode.screen ?? .dashboard {
            case .dashboard:
                let demo = DemoMode.snapshot()
                maskedKey = AnthropicKeyValidation.masked(DemoMode.appReviewKey)
                providerReports = []
                selectedProvider = nil
                state = .loaded(report: demo.report, orgName: demo.orgName)
            case .onboarding:
                maskedKey = nil
                providerReports = []
                selectedProvider = nil
                state = .needsCredentials
            }
            return
        }
        do {
            let keys = try keychain.loadAll().filter { !$0.value.isEmpty }
            guard !keys.isEmpty else {
                maskedKey = nil
                providerReports = []
                selectedProvider = nil
                state = .needsCredentials
                return
            }
            maskedKey = maskedKeys(keys)
            let cached = cache.loadAll().providerReports
            if !cached.isEmpty {
                applyLoaded(cached, selectedProvider: selectedProvider)
            }
            await refresh(using: keys)
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
            providerReports = []
            selectedProvider = nil
            state = .loaded(report: demo.report, orgName: demo.orgName)
            return .success(())
        }
        state = .loading
        return await verifyAndSave(trimmed, preserveExistingOnFailure: false)
    }

    /// Settings uses this to add/replace one provider credential in-place. A
    /// rejected replacement leaves the current dashboard, cache, and other
    /// provider credentials intact.
    func replaceCredential(using rawKey: String) async -> Result<Void, Error> {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ConnectError(message: "Paste your admin key to continue."))
        }
        if DemoMode.isReviewKey(trimmed) {
            DemoMode.isPersistedActive = true
            let demo = DemoMode.snapshot()
            maskedKey = AnthropicKeyValidation.masked(trimmed)
            providerReports = []
            selectedProvider = nil
            state = .loaded(report: demo.report, orgName: demo.orgName)
            return .success(())
        }

        let hadLoadedDashboard = state.isLoaded
        if hadLoadedDashboard { isRefreshing = true }
        defer { if hadLoadedDashboard { isRefreshing = false } }
        return await verifyAndSave(trimmed, preserveExistingOnFailure: true)
    }

    func refresh() async {
        // Demo mode never wrote to Keychain — if we try to read the key
        // here we'd get nil and bounce the user back to onboarding. Mirror
        // the bootstrap() short-circuit and just re-render the canned data.
        if DemoMode.isEnabled {
            let demo = DemoMode.snapshot()
            maskedKey = AnthropicKeyValidation.masked(DemoMode.appReviewKey)
            providerReports = []
            selectedProvider = nil
            state = .loaded(report: demo.report, orgName: demo.orgName)
            return
        }
        do {
            let keys = try keychain.loadAll().filter { !$0.value.isEmpty }
            guard !keys.isEmpty else {
                state = .needsCredentials
                maskedKey = nil
                providerReports = []
                selectedProvider = nil
                return
            }
            await refresh(using: keys)
        } catch {
            state = .failed(message: "Keychain error: \(error.localizedDescription)")
        }
    }

    func selectProviderFilter(_ provider: ProviderKind?) {
        guard !providerReports.isEmpty else { return }
        applyLoaded(providerReports, selectedProvider: provider)
    }

    func disconnect() async {
        // Demo mode never wrote to Keychain; clearing the persisted flag is
        // the only state change needed. We still call delete below in case
        // the user toggled between real and demo over the lifetime of the
        // install — it's a no-op when nothing's stored.
        DemoMode.isPersistedActive = false
        cache.clearAll()
        do {
            try keychain.deleteAll()
        } catch {
            // We still flip back to onboarding — the user clearly wants out.
            state = .failed(message: "Disconnected, but Keychain reported: \(error.localizedDescription)")
            return
        }
        maskedKey = nil
        providerReports = []
        selectedProvider = nil
        state = .needsCredentials
    }

    private func verifyAndSave(_ trimmed: String, preserveExistingOnFailure: Bool) async -> Result<Void, Error> {
        let provider = providerKind(for: trimmed)
        do {
            let identity = try await cost.whoami(apiKey: trimmed)
            if preserveExistingOnFailure {
                let report = try await cost.monthToDateCost(apiKey: trimmed)
                DemoMode.isPersistedActive = false
                try keychain.save(trimmed, for: provider)
                maskedKey = maskedKeys((try? keychain.loadAll()) ?? [provider: trimmed])
                cache.save(report: report, orgName: identity.name, for: provider)
                applyLoaded(cache.loadAll().providerReports.ifEmpty([ProviderReport(provider: provider, orgName: identity.name, report: report)]), selectedProvider: selectedProvider)
                return .success(())
            }

            // Initial connect preserves the historical behavior: a key that
            // authenticated with whoami is saved before the first cost fetch so
            // transient cost failures do not force the user to paste it again.
            DemoMode.isPersistedActive = false
            try keychain.save(trimmed, for: provider)
            maskedKey = maskedKeys((try? keychain.loadAll()) ?? [provider: trimmed])
            do {
                let report = try await cost.monthToDateCost(apiKey: trimmed)
                cache.save(report: report, orgName: identity.name, for: provider)
                applyLoaded(cache.loadAll().providerReports.ifEmpty([ProviderReport(provider: provider, orgName: identity.name, report: report)]), selectedProvider: selectedProvider)
            } catch where isProviderAuthError(error) {
                try? keychain.delete(provider)
                cache.clear(provider)
                let remaining = (try? keychain.loadAll()) ?? [:]
                maskedKey = maskedKeys(remaining)
                if remaining.isEmpty {
                    providerReports = []
                    selectedProvider = nil
                    state = .needsCredentials
                } else {
                    applyLoaded(cache.loadAll().providerReports, selectedProvider: selectedProvider)
                }
                return .failure(ConnectError(message: Self.rejectedKeyMessage))
            } catch {
                state = .failed(message: error.localizedDescription)
            }
            return .success(())
        } catch where isProviderAuthError(error) {
            if !preserveExistingOnFailure { state = .needsCredentials }
            return .failure(ConnectError(message: Self.rejectedKeyMessage))
        } catch {
            if !preserveExistingOnFailure { state = .needsCredentials }
            return .failure(ConnectError(message: error.localizedDescription))
        }
    }

    private func refresh(using keys: [ProviderKind: String]) async {
        let hasSomethingToShow = state.isLoaded
        if hasSomethingToShow {
            isRefreshing = true
        } else {
            state = .loading
        }
        defer { isRefreshing = false }

        var freshReports: [ProviderReport] = []
        var transientFailure: Error?
        for (provider, key) in keys.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            do {
                async let identity = cost.whoami(apiKey: key)
                async let report = cost.monthToDateCost(apiKey: key)
                let (orgID, mtd) = try await (identity, report)
                cache.save(report: mtd, orgName: orgID.name, for: provider)
                freshReports.append(ProviderReport(provider: provider, orgName: orgID.name, report: mtd))
            } catch where isProviderAuthError(error) {
                try? keychain.delete(provider)
                cache.clear(provider)
            } catch {
                transientFailure = error
            }
        }

        let remainingKeys = (try? keychain.loadAll()) ?? [:]
        maskedKey = maskedKeys(remainingKeys)
        let cachedReportsByProvider = Dictionary(uniqueKeysWithValues: cache.loadAll().providerReports.map { ($0.provider, $0) })
        let freshReportsByProvider = Dictionary(uniqueKeysWithValues: freshReports.map { ($0.provider, $0) })
        let reports = Array(cachedReportsByProvider.merging(freshReportsByProvider) { _, fresh in fresh }.values)
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
        if !reports.isEmpty {
            applyLoaded(reports, selectedProvider: selectedProvider)
        } else if remainingKeys.isEmpty {
            maskedKey = nil
            providerReports = []
            selectedProvider = nil
            state = .needsCredentials
        } else if !hasSomethingToShow {
            state = .failed(message: transientFailure?.localizedDescription ?? "Couldn't load your usage.")
        }
    }

    private func applyLoaded(_ reports: [ProviderReport], selectedProvider provider: ProviderKind?) {
        guard !reports.isEmpty else { return }
        let sorted = reports.sorted { $0.provider.rawValue < $1.provider.rawValue }
        providerReports = sorted
        let effectiveSelection = provider.flatMap { selected in
            sorted.contains(where: { $0.provider == selected }) ? selected : nil
        }
        selectedProvider = effectiveSelection
        let visible = effectiveSelection.map { selected in sorted.filter { $0.provider == selected } } ?? sorted
        let report = visible.count == 1 ? visible[0].report : combineMTDCosts(visible.map { $0.report })
        let orgName: String
        if effectiveSelection != nil {
            orgName = visible[0].orgName
        } else if sorted.count == 1 {
            orgName = sorted[0].orgName
        } else {
            orgName = "All providers"
        }
        state = .loaded(report: report, orgName: orgName)
    }

    private func maskedKeys(_ keys: [ProviderKind: String]) -> String? {
        guard !keys.isEmpty else { return nil }
        return keys.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { provider, key in "\(provider.displayName): \(AnthropicKeyValidation.masked(key))" }
            .joined(separator: " · ")
    }
    private static let rejectedKeyMessage =
        "Your provider rejected this key. Double-check that you copied the right admin/project key and try again."
}
