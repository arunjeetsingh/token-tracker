import Foundation

struct ProviderReport: Equatable {
    let provider: ProviderKind
    let orgName: String
    let report: MTDCost
}

enum DashboardState: Equatable {
    case needsCredentials
    case idle
    case loading
    case loaded(report: MTDCost, orgName: String)
    case failed(message: String)

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    var orgName: String? {
        if case .loaded(_, let name) = self { return name }
        return nil
    }
}


extension Dictionary where Key == ProviderKind, Value == (report: MTDCost, orgName: String) {
    var providerReports: [ProviderReport] {
        sorted { $0.key.rawValue < $1.key.rawValue }
            .map { provider, cached in
                ProviderReport(provider: provider, orgName: cached.orgName, report: cached.report)
            }
    }
}

extension Array {
    func ifEmpty(_ fallback: [Element]) -> [Element] { isEmpty ? fallback : self }
}
