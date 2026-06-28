import Foundation

/// Persists the last successfully-loaded dashboard report to `UserDefaults`
/// so the app can render previous data on launch while a fresh refresh is
/// in-flight, instead of staring at an empty screen. Snapshots are keyed by
/// provider so a multi-provider dashboard can show combined/all and provider
/// filtered views without flashing another provider's stale data.
enum DashboardCache {
    private static let storeKey = "DashboardCache.snapshot.v2"
    private static let legacyStoreKey = "DashboardCache.snapshot.v1"
    private static let store = UserDefaults.standard

    private struct Snapshot: Codable {
        let report: MTDCost
        let orgName: String
        let savedAt: Date
    }

    private typealias SnapshotMap = [ProviderKind: Snapshot]

    static func loadAll() -> [ProviderKind: (report: MTDCost, orgName: String)] {
        var result: [ProviderKind: (report: MTDCost, orgName: String)] = [:]
        if let data = store.data(forKey: storeKey),
           let snaps = try? JSONDecoder.snapshot.decode(SnapshotMap.self, from: data) {
            for (provider, snap) in snaps {
                result[provider] = (snap.report, snap.orgName)
            }
            return result
        }
        if let legacy = loadLegacy() {
            result[.anthropic] = legacy
        }
        return result
    }

    static func load(_ provider: ProviderKind) -> (report: MTDCost, orgName: String)? {
        loadAll()[provider]
    }

    /// Legacy single-provider accessor used by older call sites/tests.
    static func load() -> (report: MTDCost, orgName: String)? {
        let all = loadAll()
        if all.count == 1 { return all.values.first }
        return all[.anthropic] ?? all[.openAI]
    }

    static func save(report: MTDCost, orgName: String, for provider: ProviderKind) {
        var snaps = loadSnapshotMap()
        snaps[provider] = Snapshot(report: report, orgName: orgName, savedAt: Date())
        saveSnapshotMap(snaps)
    }

    /// Legacy single-provider save.
    static func save(report: MTDCost, orgName: String) {
        save(report: report, orgName: orgName, for: .anthropic)
    }

    static func clear(_ provider: ProviderKind) {
        var snaps = loadSnapshotMap()
        snaps.removeValue(forKey: provider)
        saveSnapshotMap(snaps)
    }

    static func clearAll() {
        store.removeObject(forKey: storeKey)
        store.removeObject(forKey: legacyStoreKey)
    }

    /// Legacy single-provider clear.
    static func clear() { clearAll() }

    private static func loadSnapshotMap() -> SnapshotMap {
        if let data = store.data(forKey: storeKey),
           let snaps = try? JSONDecoder.snapshot.decode(SnapshotMap.self, from: data) {
            return snaps
        }
        if let legacy = loadLegacy() {
            return [.anthropic: Snapshot(report: legacy.report, orgName: legacy.orgName, savedAt: Date())]
        }
        return [:]
    }

    private static func saveSnapshotMap(_ snaps: SnapshotMap) {
        if snaps.isEmpty {
            store.removeObject(forKey: storeKey)
            return
        }
        if let data = try? JSONEncoder.snapshot.encode(snaps) {
            store.set(data, forKey: storeKey)
        }
    }

    private static func loadLegacy() -> (report: MTDCost, orgName: String)? {
        guard let data = store.data(forKey: legacyStoreKey),
              let snap = try? JSONDecoder.snapshot.decode(Snapshot.self, from: data) else {
            return nil
        }
        return (snap.report, snap.orgName)
    }
}

private extension JSONEncoder {
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
