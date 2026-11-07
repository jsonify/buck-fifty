#if canImport(CoreData)
import CoreData
import Foundation
import ShoppingCore

/// One item on the restock checklist: what its purchases say, how soon it's needed and whether it's on the list.
public struct RestockLine {
    public let item: Item
    public let estimate: RestockEstimate
    public let urgency: RestockUrgency
    public let shelf: Restock.Shelf
    public let isOnList: Bool

    /// One line for what the item has been bought: "Every week · last 9 days ago", "Bought once, 3 weeks ago", or
    /// "Not bought yet".
    public func summary(now: Date, calendar: Calendar = .current) -> String {
        guard let last = estimate.lastBought else { return "Not bought yet" }
        let ago = Restock.ago(last, now: now, calendar: calendar)
        guard let rhythm = Restock.describe(interval: estimate.interval) else { return "Bought once, \(ago)" }
        return "\(rhythm) · last \(ago)"
    }
}

/// Restocking (what you'll probably need before the next trip), from the purchases trips recorded.
extension ListService {
    /// The dates of the store's ended trips that bought something (each trip's start).
    public func tripDates(at store: Store) -> [Date] {
        (store.trips ?? []).filter { $0.endedAt != nil && !$0.isDeleted }
            .compactMap { trip -> Date? in
                let route = self.route(of: trip)
                guard !route.isEmpty else { return nil }
                return trip.startedAt ?? route.first?.timestamp
            }
    }

    /// How often the store is shopped, and so when the next trip probably is.
    public func rhythm(of store: Store, calendar: Calendar = .current) -> ShoppingRhythm {
        ShoppingRhythm(tripDates: tripDates(at: store), calendar: calendar)
    }

    /// When the item was bought: its check-offs on trips that have ended.
    public func purchaseDates(of item: Item) -> [Date] {
        (item.checkOffs ?? []).filter { !$0.isDeleted && $0.trip?.endedAt != nil }.compactMap(\.timestamp)
    }

    /// Every item the store remembers, on the restock checklist: by section (needed before the next trip, soon,
    /// staples, the rest), the most urgent first within each.
    public func restockLines(in store: Store, now: Date = Date(), calendar: Calendar = .current) -> [RestockLine] {
        let trips = tripDates(at: store)
        let rhythm = ShoppingRhythm(tripDates: trips, calendar: calendar)
        let lines = (store.items ?? []).filter { !$0.isDeleted }.map { item -> RestockLine in
            let estimate = Restock.estimate(bought: purchaseDates(of: item), trips: trips, calendar: calendar)
            let urgency = Restock.urgency(of: estimate, now: now, rhythm: rhythm)
            return RestockLine(item: item, estimate: estimate, urgency: urgency,
                               shelf: Restock.shelf(urgency: urgency, isStaple: estimate.isStaple),
                               isOnList: isOnList(item))
        }
        return lines.sorted { a, b in
            if a.shelf != b.shelf { return a.shelf.rawValue < b.shelf.rawValue }
            return Restock.precedes((a.urgency, a.estimate, a.item.displayName),
                                    (b.urgency, b.estimate, b.item.displayName))
        }
    }

    /// The items needed before the next trip that aren't on the list yet, most urgent first.
    public func neededNotOnList(in store: Store, now: Date = Date(), calendar: Calendar = .current) -> [RestockLine] {
        restockLines(in: store, now: now, calendar: calendar).filter { $0.urgency.isNeeded && !$0.isOnList }
    }

    /// Puts every item needed before the next trip on the list. Returns how many it added.
    @discardableResult
    public func addNeeded(in store: Store, by shopper: Shopper, now: Date = Date(),
                          calendar: Calendar = .current) -> Int {
        let needed = neededNotOnList(in: store, now: now, calendar: calendar)
        for line in needed { addToList(line.item.displayName, store: store, by: shopper, now: now) }
        return needed.count
    }

    /// Puts a remembered item on the list, or takes it off if it's there and not yet checked off. Returns whether
    /// it's on the list now.
    @discardableResult
    public func toggleOnList(_ item: Item, by shopper: Shopper, now: Date = Date()) -> Bool {
        if let open = (item.entries ?? []).first(where: { !$0.isChecked && !$0.isDeleted }) {
            remove(open)
            return false
        }
        guard let store = item.store else { return false }
        return addToList(item.displayName, store: store, by: shopper, now: now) != nil
    }
}
#endif
