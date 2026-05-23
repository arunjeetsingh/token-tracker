import XCTest
@testable import TokenTracker

final class AnthropicClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.requests.removeAll()
        MockURLProtocol.responder = nil
    }

    private func makeClient() -> AnthropicClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
        let session = URLSession(configuration: config)
        return AnthropicClient(apiKey: "***-test", session: session)
    }

    func testWhoami() async throws {
        MockURLProtocol.responder = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "***-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            let body = #"{"id":"402418a7","type":"organization","name":"Maximum Impact"}"#
            return (200, Data(body.utf8))
        }
        let client = makeClient()
        let id = try await client.whoami()
        XCTAssertEqual(id.name, "Maximum Impact")
        XCTAssertEqual(id.type, "organization")
    }

    func testCostReportSumsPaginatedPages() async throws {
        var callCount = 0
        let page1 = """
        {
          "data": [
            {"starting_at":"2026-05-01T00:00:00Z","ending_at":"2026-05-02T00:00:00Z",
             "results":[{"currency":"USD","amount":"1000.00"}]},
            {"starting_at":"2026-05-02T00:00:00Z","ending_at":"2026-05-03T00:00:00Z",
             "results":[{"currency":"USD","amount":"500.50"}]}
          ],
          "has_more": true,
          "next_page": "page_2"
        }
        """
        let page2 = """
        {
          "data": [
            {"starting_at":"2026-05-03T00:00:00Z","ending_at":"2026-05-04T00:00:00Z",
             "results":[{"currency":"USD","amount":"250.00"}]}
          ],
          "has_more": false,
          "next_page": null
        }
        """
        MockURLProtocol.responder = { request in
            callCount += 1
            if request.url?.absoluteString.contains("page=page_2") == true {
                return (200, Data(page2.utf8))
            }
            return (200, Data(page1.utf8))
        }
        let client = makeClient()
        let start = ISO8601DateFormatter().date(from: "2026-05-01T00:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-05-23T00:00:00Z")!
        let total = try await client.totalCost(start: start, end: end)
        // 1000 + 500 + 250 = 1750 cents = $17.50
        XCTAssertEqual(total.cents, 1750)
        XCTAssertEqual(callCount, 2)
    }

    func testHTTPErrorSurfacesBody() async {
        MockURLProtocol.responder = { _ in
            (401, Data(#"{"error":"unauthorized"}"#.utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.whoami()
            XCTFail("expected error")
        } catch let err as AnthropicHTTPError {
            XCTAssertEqual(err.status, 401)
            XCTAssertTrue(err.body.contains("unauthorized"))
        } catch {
            XCTFail("expected AnthropicHTTPError, got \(error)")
        }
    }
}

// MARK: - URLProtocol mock

final class MockURLProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    static var responder: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.requests.append(request)
        guard let responder = MockURLProtocol.responder else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let (status, data) = responder(request)
        let url = request.url ?? URL(string: "https://api.anthropic.com")!
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { /* no-op */ }
}
