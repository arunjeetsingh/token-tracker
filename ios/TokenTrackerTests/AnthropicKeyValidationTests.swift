import XCTest
@testable import TokenTracker

final class AnthropicKeyValidationTests: XCTestCase {
    func testAdminKeyIsRecognized() {
        let key = "sk-ant-admin01-" + String(repeating: "A", count: 40)
        XCTAssertTrue(AnthropicKeyValidation.looksLikeAnthropicKey(key))
    }

    func testOpenAIProjectKeyIsRecognized() {
        let key = "sk-proj-" + String(repeating: "A", count: 40)
        XCTAssertTrue(AnthropicKeyValidation.looksLikeAnthropicKey(key))
    }

    func testOpenAILegacyKeyIsRecognized() {
        let key = "sk-" + String(repeating: "A", count: 40)
        XCTAssertTrue(AnthropicKeyValidation.looksLikeAnthropicKey(key))
    }

    func testApiKeyIsRecognized() {
        let key = "sk-ant-api03-" + String(repeating: "Z", count: 40)
        XCTAssertTrue(AnthropicKeyValidation.looksLikeAnthropicKey(key))
    }

    func testRandomTextIsRejected() {
        XCTAssertFalse(AnthropicKeyValidation.looksLikeAnthropicKey("hello world, here is some text"))
        XCTAssertFalse(AnthropicKeyValidation.looksLikeAnthropicKey(""))
        XCTAssertFalse(AnthropicKeyValidation.looksLikeAnthropicKey("sk-ant-admin01-short"))
    }

    func testWhitespaceIsTrimmed() {
        let key = "  sk-ant-admin01-" + String(repeating: "B", count: 40) + "\n"
        XCTAssertTrue(AnthropicKeyValidation.looksLikeAnthropicKey(key))
    }

    func testNonUrlSafeCharsRejected() {
        let key = "sk-ant-admin01-" + String(repeating: "!", count: 40)
        XCTAssertFalse(AnthropicKeyValidation.looksLikeAnthropicKey(key))
    }

    func testMaskedPreservesPrefixAndSuffix() {
        let key = "sk-ant-admin01-abcdefghijklmnopqrstuvWXYZ9"
        let masked = AnthropicKeyValidation.masked(key)
        XCTAssertTrue(masked.hasPrefix("sk-ant-admin01-"))
        XCTAssertTrue(masked.hasSuffix("WYZ9") || masked.hasSuffix("XYZ9"))
        XCTAssertTrue(masked.contains("…"))
    }

    func testShortKeyMasksFully() {
        XCTAssertEqual(AnthropicKeyValidation.masked("abc"), "••••")
    }
}
