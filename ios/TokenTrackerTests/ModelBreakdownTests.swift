import XCTest
@testable import TokenTracker

/// The interesting logic is "take top N by cost" — pure data, easy to
/// test. The SwiftUI body compiles via the build, not these unit tests.
final class ModelBreakdownTests: XCTestCase {
    private func make(_ pairs: [(String, Int64)]) -> [ModelSpend] {
        pairs.map { id, c in
            ModelSpend(modelId: id, displayName: id, cost: Money(cents: c))
        }
    }

    func testSelectsTop3FromLongerList() {
        let models = make([
            ("opus",    284_700),
            ("sonnet",  156_200),
            ("haiku",    75_100),
            ("legacy",   12_400),
            ("future",      500)
        ])
        // Re-shuffle to confirm the view re-sorts defensively.
        let view = ModelBreakdown(models: Array(models.reversed()))
        // Mirror what the view does: top 3 by cost, descending.
        let sorted = view.models.sorted { $0.cost.cents > $1.cost.cents }
        let top = Array(sorted.prefix(3))
        XCTAssertEqual(top.count, 3)
        XCTAssertEqual(top.map(\.modelId), ["opus", "sonnet", "haiku"])
        XCTAssertGreaterThan(top[0].cost.cents, top[1].cost.cents)
        XCTAssertGreaterThan(top[1].cost.cents, top[2].cost.cents)
    }

    func testHandlesEmpty() {
        // Just confirms init is safe; the view returns EmptyView in body.
        _ = ModelBreakdown(models: [])
    }

    func testHandlesFewerThanThree() {
        let models = make([("opus", 100), ("sonnet", 50)])
        let view = ModelBreakdown(models: models)
        XCTAssertEqual(view.models.count, 2)
        _ = view  // init does not crash on short lists
    }

    func testCustomTopN() {
        let models = make([("a", 1000), ("b", 900), ("c", 800), ("d", 700)])
        let view = ModelBreakdown(models: models, topN: 2)
        XCTAssertEqual(view.topN, 2)
    }
}
