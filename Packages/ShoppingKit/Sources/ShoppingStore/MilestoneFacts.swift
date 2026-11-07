#if canImport(CoreData)
import CoreData
import Foundation
import ShoppingCore

/// Milestones (issue #23): the facts about a store that say how far along its features are.
extension ListService {
    /// What the store's data says about its features. `mapsStore`, `isShared` and `tried` come from the app.
    public func milestoneFacts(for store: Store, mapsStore: Bool, isShared: Bool, tried: Set<String>,
                               calendar: Calendar = .current) -> MilestoneFacts {
        let trips = (store.trips ?? []).filter { !$0.isDeleted }
        let items = (store.items ?? []).filter { !$0.isDeleted }
        let teaching = trips.filter { $0.endedAt != nil && route(of: $0).count >= 2 }.count
        let mostBought = items.map { Restock.days(purchaseDates(of: $0), calendar: calendar).count }.max() ?? 0
        return MilestoneFacts(teachingTrips: teaching,
                              tripDays: rhythm(of: store, calendar: calendar).tripDays,
                              mostTimesBought: mostBought,
                              mappedTrips: trips.filter { !($0.path ?? "").isEmpty }.count,
                              guessedZones: items.filter(\.isZoneGuessed).count,
                              mapsStore: mapsStore, isShared: isShared, tried: tried)
    }

    /// The store's milestones (see `Milestones.all`).
    public func milestones(for store: Store, mapsStore: Bool, isShared: Bool, tried: Set<String>) -> [Milestone] {
        Milestones.all(milestoneFacts(for: store, mapsStore: mapsStore, isShared: isShared, tried: tried))
    }
}
#endif
