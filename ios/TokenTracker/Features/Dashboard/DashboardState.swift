import Foundation

enum DashboardState: Equatable {
    case needsCredentials
    case idle
    case loading
    case loaded(amount: Money, asOf: Date, orgName: String)
    case failed(message: String)
}
