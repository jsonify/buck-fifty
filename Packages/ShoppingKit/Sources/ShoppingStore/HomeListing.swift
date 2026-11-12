#if canImport(CoreData)
import CoreData
import Foundation
import ShoppingCore

/// The list at home (in your own order), Past items (everything bought before, to tap onto a new list) and what's
/// left on the list after a trip.
extension ListService {
    /// The store's list in your own order, for the list at home.
    public func homeList(in store: Store) -> [ListEntry] {
        HomeOrder.sorted(store.entries)
    }

    /// Moves the entry at `from` to `to` in `entries` (the list in your own order): each gets its new place.
    public func moveAtHome(_ entries: [ListEntry], from: Int, to: Int) {
        for (index, place) in HomeOrder.afterMove(count: entries.count, from: from, to: to) {
            entries[index].homeOrder = NSNumber(value: place)
        }
    }

    /// Everything the store remembers, for Past items: how often and when it was bought, whether it's running low,
    /// whether the last trip bought it, and whether it's on the list now.
    public func pastItems(in store: Store, now: Date = Date(), calendar: Calendar = .current) -> [PastItem<Item>] {
        let lastTrip = self.lastTrip(at: store).map { Set(items(boughtOn: $0)) } ?? []
        return restockLines(in: store, now: now, calendar: calendar).map { line in
            PastItem(ref: line.item, name: line.item.displayName, timesBought: line.estimate.timesBought,
                     lastBought: line.estimate.lastBought, isRunningLow: line.urgency.isNeeded,
                     boughtLastTrip: lastTrip.contains(line.item), isOnList: line.isOnList)
        }
    }

    /// What's still on the list and not checked off: after Done, the things the trip didn't get.
    public func leftovers(in store: Store) -> [ListEntry] {
        HomeOrder.sorted(store.entries.filter { !$0.isChecked })
    }

    /// Takes everything not checked off off the list, so the next list starts clean. Returns how many it took off.
    @discardableResult
    public func dropLeftovers(in store: Store) -> Int {
        let left = leftovers(in: store)
        for entry in left { remove(entry) }
        return left.count
    }
}
#endif
