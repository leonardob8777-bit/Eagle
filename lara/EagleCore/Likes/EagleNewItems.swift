import Foundation
import Combine

/// Which gallery items are really new: ones that appear in the Eagle Gallery after Eagle has seen that
/// gallery once. The first time a gallery loads, everything in it is taken as known (nothing is new);
/// afterwards each added item is NEW for a week, or until it is opened.
@MainActor
final class EagleNewItems: ObservableObject {
    static let shared = EagleNewItems()

    enum Kind: String {
        case wallpaper, passcode
    }

    private struct Record: Codable {
        var known: Set<String> = []
        /// First time each new item was seen.
        var fresh: [String: Date] = [:]
    }

    private static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    @Published private var records: [Kind: Record] = [:]

    private init() {
        for kind in [Kind.wallpaper, .passcode] {
            if let data = UserDefaults.standard.data(forKey: Self.storageKey(kind)),
               let record = try? JSONDecoder().decode(Record.self, from: data) {
                records[kind] = record
            }
        }
        pruneExpired()
    }

    func isNew(_ kind: Kind, _ id: String) -> Bool {
        records[kind]?.fresh[id] != nil
    }

    /// The gallery has at least one new item not yet opened.
    func hasNew(_ kind: Kind) -> Bool {
        !(records[kind]?.fresh.isEmpty ?? true)
    }

    /// Called with every item a gallery offers each time its catalog loads.
    func observe(_ kind: Kind, ids: [String]) {
        guard !ids.isEmpty else { return }
        guard var record = records[kind] else {
            // First look at this gallery: all of it is the starting point, not news.
            save(Record(known: Set(ids)), kind)
            return
        }
        let now = Date()
        let added = ids.filter { !record.known.contains($0) }
        guard !added.isEmpty else { return }
        for id in added {
            record.known.insert(id)
            record.fresh[id] = now
        }
        save(record, kind)
    }

    /// The item was opened: it is no longer news.
    func markSeen(_ kind: Kind, _ id: String) {
        guard var record = records[kind], record.fresh.removeValue(forKey: id) != nil else { return }
        save(record, kind)
    }

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-Self.lifetime)
        for (kind, record) in records {
            var pruned = record
            pruned.fresh = record.fresh.filter { $0.value > cutoff }
            if pruned.fresh.count != record.fresh.count { save(pruned, kind) }
        }
    }

    private func save(_ record: Record, _ kind: Kind) {
        records[kind] = record
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: Self.storageKey(kind))
        }
    }

    private static func storageKey(_ kind: Kind) -> String {
        "eagle.newItems.\(kind.rawValue)"
    }
}

/// The Customize options this version of Eagle brings something new to. Each shows NEW until it is
/// opened once. Kept per version, so installing a new IPA over an existing Eagle shows that version's
/// news again, while a plain relaunch remembers what was already opened.
@MainActor
final class EagleReleaseNews: ObservableObject {
    static let shared = EagleReleaseNews()

    /// What 1.0.7 brings, matching its updates window. Update it with each release (LaraHomeToolRoute ids).
    private static let version = "1.0.7"
    private static let sections: Set<String> = [
        "wallpapers", "passcode", "islandGallery", "dockGallery",
        "cards", "dock", "homeLabelColor", "completeStyles",
    ]

    private static var storageKey: String { "eagle.releaseNews.\(version).opened" }

    @Published private var opened: Set<String>

    private init() {
        opened = Set(UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? [])
    }

    func isNew(_ section: String) -> Bool {
        Self.sections.contains(section) && !opened.contains(section)
    }

    func markSeen(_ section: String) {
        guard isNew(section) else { return }
        opened.insert(section)
        UserDefaults.standard.set(Array(opened).sorted(), forKey: Self.storageKey)
    }
}
