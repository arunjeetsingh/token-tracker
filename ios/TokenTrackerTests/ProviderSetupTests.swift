import XCTest
@testable import TokenTracker

final class ProviderSetupTests: XCTestCase {
    func testDefaultSelectionPrefersAnthropicForExistingUsers() {
        XCTAssertEqual(ProviderSetup.defaultSelection, .anthropic)
        XCTAssertEqual(ProviderSetup.allCases.first, .anthropic)
    }

    func testApiKeyRoutingForAnthropicKeys() {
        XCTAssertEqual(ProviderSetup(apiKey: "  " + "sk-" + "ant-admin-" + String(repeating: "a", count: 32)), .anthropic)
        XCTAssertEqual(ProviderSetup(apiKey: "sk-" + "ant-api-" + String(repeating: "b", count: 32)), .anthropic)
    }

    func testApiKeyRoutingForOpenAIKeys() {
        XCTAssertEqual(ProviderSetup(apiKey: "sk-admin-" + String(repeating: "a", count: 32)), .openAI)
        XCTAssertEqual(ProviderSetup(apiKey: "sk-proj-" + String(repeating: "b", count: 32)), .openAI)
        XCTAssertEqual(ProviderSetup(apiKey: "sk-" + String(repeating: "c", count: 32)), .openAI)
    }

    func testApiKeyRoutingRejectsUnknownPrefixes() {
        XCTAssertNil(ProviderSetup(apiKey: "xoxb-" + String(repeating: "a", count: 32)))
    }
}
