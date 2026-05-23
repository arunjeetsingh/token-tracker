import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: DashboardState = .idle

    func bootstrap() async {
        do {
            guard let key = try KeychainStore.load(.anthropicAdminKey), !key.isEmpty else {
                state = .needsCredentials
                return
            }
            await refresh(using: key)
        } catch {
            state = .failed(message: "Keychain error: \(error.localizedDescription)")
        }
    }

    func save(apiKey: String) async {
        do {
            try KeychainStore.save(apiKey, for: .anthropicAdminKey)
            await refresh(using: apiKey)
        } catch {
            state = .failed(message: "Could not save key: \(error.localizedDescription)")
        }
    }

    func refresh() async {
        do {
            guard let key = try KeychainStore.load(.anthropicAdminKey) else {
                state = .needsCredentials
                return
            }
            await refresh(using: key)
        } catch {
            state = .failed(message: "Keychain error: \(error.localizedDescription)")
        }
    }

    private func refresh(using key: String) async {
        state = .loading
        let client = AnthropicClient(apiKey: key)
        do {
            async let identity = client.whoami()
            async let amount = client.monthToDateCost()
            let (orgID, total) = try await (identity, amount)
            state = .loaded(amount: total, asOf: Date(), orgName: orgID.name)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}
