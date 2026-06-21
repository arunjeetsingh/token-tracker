import XCTest
@testable import TokenTracker

final class OpenAIClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.requests.removeAll()
        MockURLProtocol.responder = nil
    }

    private func makeClient() -> OpenAIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
        let session = URLSession(configuration: config)
        return OpenAIClient(apiKey: " [REDACTED] ", session: session)
    }

    func testProviderKindRoutesAnthropicPrefixAndDefaultsToOpenAI() {
        XCTAssertEqual(providerKind(for: "  sk-ant-[REDACTED]  "), .anthropic)
        XCTAssertEqual(providerKind(for: "[REDACTED]"), .openAI)
    }

    func testWhoamiProbesCostsEndpointWithBearerAuth() async throws {
        MockURLProtocol.responder = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer [REDACTED]")
            XCTAssertEqual(request.value(forHTTPHeaderField: "accept"), "application/json")
            XCTAssertEqual(request.url?.path, "/v1/organization/costs")
            let urlString = request.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("start_time=1780099200"))
            XCTAssertTrue(urlString.contains("end_time=1780185600"))
            XCTAssertTrue(urlString.contains("bucket_width=1d"))
            XCTAssertTrue(urlString.contains("group_by%5B%5D=line_item") || urlString.contains("group_by[]=line_item"))
            XCTAssertTrue(urlString.contains("limit=1"))
            return (200, Data(#"{"data":[],"has_more":false,"next_page":null}"#.utf8))
        }

        let now = ISO8601DateFormatter().date(from: "2026-05-30T12:00:00Z")!
        let org = try await makeClient().whoami(now: now)

        XCTAssertEqual(org.id, "openai")
        XCTAssertEqual(org.name, "OpenAI Organization")
    }

    func testMonthToDateCostConvertsUSDAmountsAndBuildsDailyAndBreakdown() async throws {
        let body = """
        {
          "data": [
            {"start_time":1777507200,"end_time":1777593600,"results":[
              {"amount":{"value":"99.99","currency":"usd"},"line_item":"model:gpt-4.1"}
            ]},
            {"start_time":1780012800,"end_time":1780099200,"results":[
              {"amount":{"value":"12.345","currency":"usd"},"line_item":"model:gpt-4.1"},
              {"amount":{"value":"0.335","currency":"usd"},"line_item":"batch_api"},
              {"amount":{"value":"4.00","currency":"usd"},"line_item":null,"project_id":"proj_alpha"}
            ]},
            {"start_time":1780099200,"end_time":1780185600,"results":[
              {"amount":{"value":"20.00","currency":"usd"},"line_item":"model:gpt-4o-mini"}
            ]}
          ],
          "has_more": false,
          "next_page": null
        }
        """
        MockURLProtocol.responder = { _ in (200, Data(body.utf8)) }
        let now = ISO8601DateFormatter().date(from: "2026-05-30T12:00:00Z")!

        let report = try await makeClient().monthToDateCost(now: now)

        // Prior-month sparkline row is kept in dailySpend but excluded from MTD.
        XCTAssertEqual(report.dailySpend.count, 3)
        XCTAssertEqual(report.dailySpend.first?.date, ISO8601DateFormatter().date(from: "2026-04-30T00:00:00Z"))
        // MTD = 12.345 -> 1234¢ (bankers), 0.335 -> 34¢, 4.00 -> 400¢, 20.00 -> 2000¢.
        XCTAssertEqual(report.finalizedCost.cents, 3668)
        XCTAssertEqual(report.todayEstimatedCost, .zero)
        XCTAssertEqual(report.finalizedThrough, ISO8601DateFormatter().date(from: "2026-05-31T00:00:00Z"))
        XCTAssertTrue(report.unpricedModels.isEmpty)

        XCTAssertEqual(report.modelBreakdown.count, 4)
        XCTAssertEqual(report.modelBreakdown[0].modelId, "model:gpt-4o-mini")
        XCTAssertEqual(report.modelBreakdown[0].displayName, "GPT 4o Mini")
        XCTAssertEqual(report.modelBreakdown[0].cost.cents, 2000)
        XCTAssertEqual(report.modelBreakdown[1].modelId, "model:gpt-4.1")
        XCTAssertEqual(report.modelBreakdown[1].cost.cents, 1234)
        XCTAssertEqual(report.modelBreakdown[2].modelId, "proj_alpha")
        XCTAssertEqual(report.modelBreakdown[2].cost.cents, 400)
        XCTAssertEqual(report.modelBreakdown[3].modelId, "batch_api")
        XCTAssertEqual(report.modelBreakdown[3].displayName, "Batch API")
        XCTAssertEqual(report.modelBreakdown[3].cost.cents, 34)
    }

    func testMonthToDateCostFollowsPaginationAcrossPages() async throws {
        let page1 = """
        {
          "data": [
            {"start_time":1780876800,"results":[
              {"amount":{"value":"1.00","currency":"usd"},"line_item":"model:gpt-4.1"}
            ]}
          ],
          "has_more": true,
          "next_page": "page_2"
        }
        """
        let page2 = """
        {
          "data": [
            {"start_time":1780876800,"results":[
              {"amount":{"value":"2.00","currency":"usd"},"line_item":"model:gpt-4.1"}
            ]}
          ],
          "has_more": false,
          "next_page": null
        }
        """
        MockURLProtocol.responder = { request in
            if request.url?.absoluteString.contains("page=page_2") == true {
                return (200, Data(page2.utf8))
            }
            return (200, Data(page1.utf8))
        }
        let now = ISO8601DateFormatter().date(from: "2026-06-08T12:00:00Z")!

        let report = try await makeClient().monthToDateCost(now: now)

        XCTAssertEqual(report.finalizedCost.cents, 300)
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        XCTAssertTrue(MockURLProtocol.requests[1].url?.absoluteString.contains("page=page_2") == true)
    }

    func testHTTP401IsProviderAuthError() async {
        MockURLProtocol.responder = { _ in
            (401, Data(#"{"error":"unauthorized"}"#.utf8))
        }

        do {
            let now = ISO8601DateFormatter().date(from: "2026-05-30T12:00:00Z")!
            _ = try await makeClient().whoami(now: now)
            XCTFail("expected error")
        } catch let error as OpenAIHTTPError {
            XCTAssertEqual(error.status, 401)
            XCTAssertTrue(error.body.contains("unauthorized"))
            XCTAssertTrue(isProviderAuthError(error))
        } catch {
            XCTFail("expected OpenAIHTTPError, got \(error)")
        }
    }
}
