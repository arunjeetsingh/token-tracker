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

    func testTodayEstimatedCostFromUsageReport() async throws {
        // Hourly bucket with all 5 token lanes on opus-4-7. Pricing × tokens
        // should land at exactly 19.8093 (matches our live probe).
        let body = """
        {
          "data": [
            {"starting_at":"2026-05-24T14:00:00Z","ending_at":"2026-05-24T15:00:00Z",
             "results":[{
               "model":"claude-opus-4-7",
               "uncached_input_tokens":240,
               "cache_creation":{"ephemeral_5m_input_tokens":2033453,"ephemeral_1h_input_tokens":0},
               "cache_read_input_tokens":11185860,
               "output_tokens":60244,
               "server_tool_use":{"web_search_requests":0}
             }]}
          ],
          "has_more": false,
          "next_page": null
        }
        """
        var capturedURL: URL?
        MockURLProtocol.responder = { request in
            capturedURL = request.url
            return (200, Data(body.utf8))
        }
        let client = makeClient()
        let estimate = try await client.todayEstimatedCost()
        XCTAssertEqual(estimate.cost.cents, 1981) // $19.81 rounded
        XCTAssertTrue(estimate.unpricedModels.isEmpty)
        // Confirm we hit the right endpoint and asked for hourly buckets grouped by model.
        let urlStr = capturedURL?.absoluteString ?? ""
        XCTAssertTrue(urlStr.contains("/v1/organizations/usage_report/messages"))
        XCTAssertTrue(urlStr.contains("bucket_width=1h"))
        XCTAssertTrue(urlStr.contains("group_by%5B%5D=model") || urlStr.contains("group_by[]=model"))
    }

    func testTodayEstimateReportsUnpricedModels() async throws {
        let body = """
        {
          "data": [
            {"starting_at":"2026-05-24T14:00:00Z","ending_at":"2026-05-24T15:00:00Z",
             "results":[{
               "model":"claude-future-9000",
               "uncached_input_tokens":1000,
               "cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},
               "cache_read_input_tokens":0,
               "output_tokens":500,
               "server_tool_use":{"web_search_requests":0}
             }]}
          ],
          "has_more": false,
          "next_page": null
        }
        """
        MockURLProtocol.responder = { _ in (200, Data(body.utf8)) }
        let estimate = try await makeClient().todayEstimatedCost()
        XCTAssertEqual(estimate.cost.cents, 0)
        XCTAssertEqual(estimate.unpricedModels, ["claude-future-9000"])
    }

    func testMonthToDateCombinesFinalizedAndEstimate() async throws {
        // Two endpoints, dispatch by path.
        // amount is in cents (per Anthropic's quirk); 50000 cents = $500.00
        let costPage = """
        {
          "data": [
            {"starting_at":"2026-05-01T00:00:00Z","ending_at":"2026-05-02T00:00:00Z",
             "results":[{"currency":"USD","amount":"50000.00"}]}
          ],
          "has_more": false,
          "next_page": null
        }
        """
        let usagePage = """
        {
          "data": [
            {"starting_at":"2026-05-24T14:00:00Z","ending_at":"2026-05-24T15:00:00Z",
             "results":[{
               "model":"claude-opus-4-7",
               "uncached_input_tokens":240,
               "cache_creation":{"ephemeral_5m_input_tokens":2033453,"ephemeral_1h_input_tokens":0},
               "cache_read_input_tokens":11185860,
               "output_tokens":60244,
               "server_tool_use":{"web_search_requests":0}
             }]}
          ],
          "has_more": false,
          "next_page": null
        }
        """
        MockURLProtocol.responder = { request in
            let path = request.url?.path ?? ""
            if path.contains("cost_report") {
                return (200, Data(costPage.utf8))
            }
            return (200, Data(usagePage.utf8))
        }
        // Pick a "now" mid-month so finalized window is non-empty.
        let now = ISO8601DateFormatter().date(from: "2026-05-24T14:30:00Z")!
        let report = try await makeClient().monthToDateCost(now: now)
        XCTAssertEqual(report.finalizedCost.cents, 50000)         // $500.00
        XCTAssertEqual(report.todayEstimatedCost.cents, 1981)     // $19.81 estimate
        XCTAssertEqual(report.total.cents, 51981)                 // $519.81
        XCTAssertTrue(report.hasTodayEstimate)
        XCTAssertFalse(report.hasUnpricedModels)
    }

    func testCostReportPopulatesDailyAndModelBreakdown() async throws {
        // Two days, two models per day. cost_report grouped by model returns
        // one row per (day, model). Sparkline gets daily sums, breakdown
        // gets per-model sums across the window.
        let body = """
        {
          "data": [
            {"starting_at":"2026-05-20T00:00:00Z","ending_at":"2026-05-21T00:00:00Z",
             "results":[
               {"currency":"USD","amount":"30000.00","model":"claude-opus-4-7"},
               {"currency":"USD","amount":"10000.00","model":"claude-sonnet-4-5"}
             ]},
            {"starting_at":"2026-05-21T00:00:00Z","ending_at":"2026-05-22T00:00:00Z",
             "results":[
               {"currency":"USD","amount":"50000.00","model":"claude-opus-4-7"},
               {"currency":"USD","amount":"15000.00","model":"claude-haiku-4-5"}
             ]}
          ],
          "has_more": false,
          "next_page": null
        }
        """
        var capturedURL: URL?
        MockURLProtocol.responder = { request in
            capturedURL = request.url
            return (200, Data(body.utf8))
        }
        let client = makeClient()
        let start = ISO8601DateFormatter().date(from: "2026-05-20T00:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-05-22T00:00:00Z")!
        let detail = try await client.costDetail(start: start, end: end)

        // Two days, sorted chronologically.
        XCTAssertEqual(detail.daily.count, 2)
        XCTAssertEqual(detail.daily[0].cost.cents, 30000 + 10000) // $400
        XCTAssertEqual(detail.daily[1].cost.cents, 50000 + 15000) // $650
        // Per-model totals across the window.
        XCTAssertEqual(detail.perModel["claude-opus-4-7"]?.reduce(Money.zero) { $0 + $1.cost }.cents, 80000)
        XCTAssertEqual(detail.perModel["claude-sonnet-4-5"]?.reduce(Money.zero) { $0 + $1.cost }.cents, 10000)
        XCTAssertEqual(detail.perModel["claude-haiku-4-5"]?.reduce(Money.zero) { $0 + $1.cost }.cents, 15000)

        // Confirm we asked for daily buckets grouped by model.
        let urlStr = capturedURL?.absoluteString ?? ""
        XCTAssertTrue(urlStr.contains("bucket_width=1d"))
        XCTAssertTrue(urlStr.contains("group_by%5B%5D=model") || urlStr.contains("group_by[]=model"))
    }

    func testMonthToDateExposesSparklineAndBreakdown() async throws {
        // cost_report covers the 30-day sparkline window. Hero MTD is the
        // in-month subset; breakdown is also in-month per model.
        let costPage = """
        {
          "data": [
            {"starting_at":"2026-05-20T00:00:00Z","ending_at":"2026-05-21T00:00:00Z",
             "results":[
               {"currency":"USD","amount":"30000.00","model":"claude-opus-4-7"},
               {"currency":"USD","amount":"10000.00","model":"claude-sonnet-4-5"}
             ]},
            {"starting_at":"2026-05-21T00:00:00Z","ending_at":"2026-05-22T00:00:00Z",
             "results":[
               {"currency":"USD","amount":"50000.00","model":"claude-opus-4-7"},
               {"currency":"USD","amount":"15000.00","model":"claude-haiku-4-5"}
             ]}
          ],
          "has_more": false,
          "next_page": null
        }
        """
        let usagePage = """
        {
          "data": [
            {"starting_at":"2026-05-24T14:00:00Z","ending_at":"2026-05-24T15:00:00Z",
             "results":[]}
          ],
          "has_more": false,
          "next_page": null
        }
        """
        MockURLProtocol.responder = { request in
            let path = request.url?.path ?? ""
            if path.contains("cost_report") {
                return (200, Data(costPage.utf8))
            }
            return (200, Data(usagePage.utf8))
        }
        let now = ISO8601DateFormatter().date(from: "2026-05-24T14:30:00Z")!
        let report = try await makeClient().monthToDateCost(now: now)
        XCTAssertEqual(report.dailySpend.count, 2)
        XCTAssertEqual(report.modelBreakdown.count, 3)
        // Breakdown is sorted descending by cost.
        XCTAssertEqual(report.modelBreakdown[0].modelId, "claude-opus-4-7")
        XCTAssertGreaterThan(report.modelBreakdown[0].cost.cents, report.modelBreakdown[1].cost.cents)
        XCTAssertEqual(report.modelBreakdown[0].displayName, "Claude Opus 4.7")
        // MTD finalized = sum of daily sums.
        XCTAssertEqual(report.finalizedCost.cents, 30000 + 10000 + 50000 + 15000)
    }

    func testDisplayNameForKnownModelIds() {
        XCTAssertEqual(AnthropicClient.displayName(forModelId: "claude-opus-4-7"),   "Claude Opus 4.7")
        XCTAssertEqual(AnthropicClient.displayName(forModelId: "claude-opus-4-5"),   "Claude Opus 4.5")
        XCTAssertEqual(AnthropicClient.displayName(forModelId: "claude-sonnet-4-5"), "Claude Sonnet 4.5")
        XCTAssertEqual(AnthropicClient.displayName(forModelId: "claude-haiku-4-5"),  "Claude Haiku 4.5")
        XCTAssertEqual(AnthropicClient.displayName(forModelId: "claude-3-5-sonnet"), "Claude Sonnet 3.5")
        XCTAssertEqual(AnthropicClient.displayName(forModelId: "claude-3-5-haiku"),  "Claude Haiku 3.5")
        // Unknown id falls through unchanged.
        XCTAssertEqual(AnthropicClient.displayName(forModelId: "some-future-model"), "some-future-model")
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
