import Foundation

/// Dependency seams for `DashboardViewModel`.
///
/// The view model orchestrates three collaborators — the Anthropic cost API,
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

/// Fetches organization identity and month-to-date cost for a given admin key.
/// The key is passed per call so the view model never has to hold a live
/// client instance (and so a mock can vary its response per key).
protocol CostProviding {
    func whoami(apiKey: String) async throws -> AnthropicAPI.OrgIdentity
    func monthToDateCost(apiKey: String) async throws -> MTDCost
}

/// Reads / writes the single Anthropic admin-key slot in the Keychain.
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

// MARK: - Production implementations

/// Wraps `AnthropicClient`. A fresh client is created per call; construction is
/// trivial (no network) and the two calls in `refresh(using:)` still run
/// concurrently via the view model's `async let`.
struct LiveCostProvider: CostProviding {
    func whoami(apiKey: String) async throws -> AnthropicAPI.OrgIdentity {
        try await AnthropicClient(apiKey: apiKey).whoami()
    }

    func monthToDateCost(apiKey: String) async throws -> MTDCost {
        try await AnthropicClient(apiKey: apiKey).monthToDateCost()
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
