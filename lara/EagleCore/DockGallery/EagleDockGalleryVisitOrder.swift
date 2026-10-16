import Foundation

/// Pure catalog reconciliation and first-theme choices for a Gallery visit.
/// The screen supplies the random order and owns selection/storage effects.
nonisolated enum EagleDockGalleryVisitOrder {
    struct PendingUpdate: Sendable {
        let retainedIDs: [String]
        let additions: [String]

        /// Reads visit history only for a fresh order, synchronously and once.
        /// Randomization and committing the resulting order remain with the caller.
        func resolvedOrder(
            shuffledAdditions: [String],
            lastViewedStaticID: @autoclosure () -> String,
            lastViewedLiveID: @autoclosure () -> String,
            themes: @autoclosure () -> [EagleDockGalleryTheme]
        ) -> [String] {
            let order = retainedIDs + shuffledAdditions
            guard retainedIDs.isEmpty else { return order }
            return EagleDockGalleryVisitOrder.avoidingLastViewed(
                order: order,
                lastViewedStaticID: lastViewedStaticID(),
                lastViewedLiveID: lastViewedLiveID(),
                themes: themes()
            )
        }
    }

    static func pendingUpdate(
        themes: [EagleDockGalleryTheme],
        orderedIDs: [String]
    ) -> PendingUpdate {
        let catalogIDs = Set(themes.map(\.id))
        let retainedIDs = orderedIDs.filter { catalogIDs.contains($0) }
        let retainedSet = Set(retainedIDs)
        let additions = Array(catalogIDs.subtracting(retainedSet))
        return PendingUpdate(retainedIDs: retainedIDs, additions: additions)
    }

    static func avoidingLastViewed(
        order initialOrder: [String],
        lastViewedStaticID: String,
        lastViewedLiveID: String,
        themes: [EagleDockGalleryTheme]
    ) -> [String] {
        var order = initialOrder
        for (filter, lastID) in [(EagleDockGalleryMediaFilter.still, lastViewedStaticID), (.live, lastViewedLiveID)] {
            let categoryIDs = Set(themes.filter {
                filter.includes($0, favorites: [])
            }.map(\.id))
            let indices = order.indices.filter { categoryIDs.contains(order[$0]) }
            if indices.count > 1, let first = indices.first, order[first] == lastID {
                order.swapAt(first, indices[1])
            }
        }
        return order
    }
}
