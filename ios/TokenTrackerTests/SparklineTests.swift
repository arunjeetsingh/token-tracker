import XCTest
@testable import TokenTracker

/// SwiftUI view rendering is awkward to unit-test. We instead validate the
/// pure-function point-projection helper, plus instantiate the view with
/// edge-case data to confirm it doesn't crash at init time. The build
/// itself (`xcodebuild test`) covers the SwiftUI body compile path.
final class SparklineTests: XCTestCase {
    private func make(_ cents: [Int64]) -> [DailySpend] {
        let base = Date(timeIntervalSince1970: 1_716_000_000)
        return cents.enumerated().map { idx, c in
            DailySpend(date: base.addingTimeInterval(TimeInterval(idx * 86_400)),
                       cost: Money(cents: c))
        }
    }

    func testPointsEmpty() {
        XCTAssertTrue(Sparkline.points(for: [], in: CGSize(width: 100, height: 80)).isEmpty)
    }

    func testPointsSingle() {
        let one = make([100])
        XCTAssertTrue(Sparkline.points(for: one, in: CGSize(width: 100, height: 80)).isEmpty,
                      "Single point should fall to empty placeholder")
    }

    func testPointsTwo() {
        let two = make([100, 200])
        let pts = Sparkline.points(for: two, in: CGSize(width: 100, height: 80))
        XCTAssertEqual(pts.count, 2)
        XCTAssertEqual(Double(pts.first!.x), 0, accuracy: 0.0001)
        XCTAssertEqual(Double(pts.last!.x), 100, accuracy: 0.0001)
        // Higher value plots higher on screen (smaller y).
        XCTAssertLessThan(pts.last!.y, pts.first!.y)
    }

    func testPointsThirty() {
        let many = make((1...30).map { Int64($0 * 1_000) })
        let pts = Sparkline.points(for: many, in: CGSize(width: 300, height: 80))
        XCTAssertEqual(pts.count, 30)
        // Monotone-increasing input -> monotone-decreasing y.
        for (a, b) in zip(pts, pts.dropFirst()) {
            XCTAssertLessThan(b.y, a.y + 0.0001)
            XCTAssertGreaterThan(b.x, a.x)
        }
        // None of the points overflow the canvas.
        for p in pts {
            XCTAssertGreaterThanOrEqual(p.y, 0)
            XCTAssertLessThanOrEqual(p.y, 80)
            XCTAssertGreaterThanOrEqual(p.x, 0)
            XCTAssertLessThanOrEqual(p.x, 300 + 0.0001)
        }
    }

    func testPointsFlatSeriesDoesNotDivideByZero() {
        let flat = make([500, 500, 500, 500])
        let pts = Sparkline.points(for: flat, in: CGSize(width: 100, height: 80))
        XCTAssertEqual(pts.count, 4)
        // All on the same horizontal line (the bottom-ish), no NaNs.
        for p in pts {
            XCTAssertFalse(p.y.isNaN)
            XCTAssertFalse(p.x.isNaN)
        }
    }

    func testViewInitDoesNotCrashOnEdgeCases() {
        // SwiftUI view init shouldn't blow up on empty / single-point input.
        _ = Sparkline(data: [])
        _ = Sparkline(data: make([42]))
        _ = Sparkline(data: make([1, 2]))
        _ = Sparkline(data: make(Array(repeating: Int64(100), count: 30)))
    }
}
