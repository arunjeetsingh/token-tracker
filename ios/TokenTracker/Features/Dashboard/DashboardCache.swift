import Foundation

/// Persists the last successfully-loaded dashboard report to `UserDefaults`
/// so the app can render previous data on launch while a fresh refresh is
/// in-flight, instead of staring at an empty screen.
///
/// Design notes:
/// - We deliberately use `UserDefaults` rather than the Keychain. The cached
///   report is non-sensitive (totals, daily series, model breakdown), and
///   it's keyed alongside the bundle so it disappears with the app.
/// - The cache is *not* used for Demo Mode — DemoMode short-circuits before
///   we ever consult the cache, so reviewers always see canned data.
/// - On any decode failure (schema drift, partial write) we silently
///   discard. Stale cached data is never worse than no cached data because
///   the dashboard always shows the "as of" timestamp from the report.
enum DashboardCache {
    private static let storeKey = "DashboardCache.snapshot.v1"
    private static let store = UserDefaults.standard

    private struct Snapshot: Codable {
        let report: MTDCost
        let orgName: String
        let savedAt: Date
    }

    /// Load the last cached report, if any. Returns nil on miss or decode
    /// failure.
    static func load() -> (report: MTDCost, orgName: String)? {
        guard let data = store.data(forKey: storeKey) else { return nil }
        do {
            let snap = try JSONDecoder.snapshot.decode(Snapshot.self, from: data)
            return (snap.report, snap.orgName)
        } catch {
            // Old or partial blob — drop it on the floor and behave like a
            // cache miss. We don't want a single bad write to lock the app
            // out of cached data forever.
            return nil
        }
    }

    /// Persist a freshly-loaded report. Errors are ignored intentionally —
    /// failing to cache should never surface to the user.
    static func save(report: MTDCost, orgName: String) {
        let snap = Snapshot(report: report, orgName: orgName, savedAt: Date())
        if let data = try? JSONEncoder.snapshot.encode(snap) {
            store.set(data, forKey: storeKey)
        }
    }

    /// Drop the cached snapshot. Called on disconnect so a new connection
    /// doesn't briefly flash the previous owner's data.
    static func clear() {
        store.removeObject(forKey: storeKey)
    }
}

private extension JSONEncoder {
    /// Shared encoder configured for the cache: ISO-8601 dates so
    /// round-tripping is stable across timezones / locales.
    static let snapshot: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let snapshot: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
