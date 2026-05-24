import Foundation

enum DashboardState: Equatable {
    case needsCredentials
    case idle
    case loading
    case loaded(amount: Money, asOf: Date, orgName: String)
    case failed(message: String)

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    var orgName: String? {
        if case .loaded(_, _, let name) = self { return name }
        return nil
    }
}
