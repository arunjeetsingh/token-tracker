import Foundation

/// Dependency seams for `DashboardViewModel`.
///
/// The view model orchestrates three collaborators — the provider cost API,
/// the Keychain-backed credential store, and the on-device report cache. In
/// production each protocol is a thin wrapper over the existing concrete type
/// (`AnthropicClient`, `KeychainStore`, `DashboardCache`); tests substitute
/// lightweight mocks. The protocols are intentionally scoped to *exactly* what
/// the view model needs — one credential slot, no API key argument on the
/// store — so both the wrappers and the test doubles stay trivial.
///
/// `DemoMode` is deliberately *not* abstracted here: it already exposes a
/// `defaultsOverride` test seam and is consulted as a static, so threading it
/// through the initializer would add surface area for no testability gain.

/// Fetches organization identity and month-to-date cost for a given provider key.
/// The key is passed per call so the view model never has to hold a live client
/// instance; the live wrapper builds a throwaway provider client each call.
protocol CostProviding {
    func whoami(apiKey: String) async throws -> AnthropicAPI.OrgIdentity
    func monthToDateCost(apiKey: String) async throws -> MTDCost
}

enum ProviderKind: Equatable {
    case anthropic
    case openAI
}

func providerKind(for apiKey: String) -> ProviderKind {
    apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-ant-") ? .anthropic : .openAI
}

/// Reads / writes the single provider API-key slot in the Keychain.
protocol CredentialStoring {
    func load() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}

/// Persists / restores the last dashboard snapshot for instant cold launch.
protocol ReportCaching {
    func load() -> (report: MTDCost, orgName: String)?
    func save(report: MTDCost, orgName: String)
    func clear()
}

/// On-device monthly spend-limit *target* (cents, nil = unset). The Admin API
/// can't read or set the org's real limit, so this is a local tracking value.
protocol SpendLimitStoring {
    var limitCents: Int64? { get set }
}

/// Persists the spend-alert opt-in plus a once-per-month dedupe marker.
protocol NotificationPreferenceStoring {
    var alertEnabled: Bool { get set }
    var lastAlertedMonth: String? { get set }
}

// MARK: - Production implementations

/// Wraps the live Anthropic/OpenAI clients. A fresh client is created per call;
/// construction is cheap — no network, and decoders are held by the clients — so
/// the two calls in `refresh(using:)` still run concurrently via the view model's
/// `async let`.
struct LiveCostProvider: CostProviding {
    func whoami(apiKey: String) async throws -> AnthropicAPI.OrgIdentity {
        switch providerKind(for: apiKey) {
        case .anthropic:
            try await AnthropicClient(apiKey: apiKey).whoami()
        case .openAI:
            try await OpenAIClient(apiKey: apiKey).whoami()
        }
    }

    func monthToDateCost(apiKey: String) async throws -> MTDCost {
        switch providerKind(for: apiKey) {
        case .anthropic:
            try await AnthropicClient(apiKey: apiKey).monthToDateCost()
        case .openAI:
            try await OpenAIClient(apiKey: apiKey).monthToDateCost()
        }
    }
}

struct LiveCredentialStore: CredentialStoring {
    func load() throws -> String? { try KeychainStore.load(.anthropicAdminKey) }
    func save(_ value: String) throws { try KeychainStore.save(value, for: .anthropicAdminKey) }
    func delete() throws { try KeychainStore.delete(.anthropicAdminKey) }
}

struct LiveReportCache: ReportCaching {
    func load() -> (report: MTDCost, orgName: String)? { DashboardCache.load() }
    func save(report: MTDCost, orgName: String) { DashboardCache.save(report: report, orgName: orgName) }
    func clear() { DashboardCache.clear() }
}

/// UserDefaults-backed local spend limit. Non-sensitive, so it sits alongside
/// the report cache rather than in the Keychain.
struct LiveSpendLimitStore: SpendLimitStoring {
    private let defaults: UserDefaults
    private let key = "SpendLimit.cents.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var limitCents: Int64? {
        get { (defaults.object(forKey: key) as? NSNumber)?.int64Value }
        set {
            if let newValue {
                defaults.set(NSNumber(value: newValue), forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

/// UserDefaults-backed spend-alert preferences. Default: alerts off (we only
/// request notification permission when the user turns this on).
struct LiveNotificationPrefs: NotificationPreferenceStoring {
    private let defaults: UserDefaults
    private let enabledKey = "SpendAlert.enabled.v1"
    private let lastMonthKey = "SpendAlert.lastMonth.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var alertEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    var lastAlertedMonth: String? {
        get { defaults.string(forKey: lastMonthKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: lastMonthKey)
            } else {
                defaults.removeObject(forKey: lastMonthKey)
            }
        }
    }
}
