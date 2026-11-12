import Foundation

/// What the list at home needs to know about an entry: the place you dragged it to, and when it was added.
public protocol HomeOrderable {
    /// Its place in your own order (smaller first); nil for an entry from before there was one.
    var homePlace: Double? { get }
    /// When it went on the list.
    var addedAt: Date? { get }
    var sortName: String { get }
}

/// The list at home, before the trip: in your own order, the way you'd write it on paper or in a notes app. New things
/// go at the bottom; drag one to move it. Only in the store does the list sort itself into walking order
/// (`ListOrdering`).
public enum HomeOrder {
    /// `entries` in your order: by their place, then (for ones without a place) by when they were added, at the end.
    public static func sorted<E: HomeOrderable>(_ entries: [E]) -> [E] {
        entries.sorted { a, b in
            switch (a.homePlace, b.homePlace) {
            case let (x?, y?) where x != y: return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            default: break
            }
            let ta = a.addedAt ?? .distantPast, tb = b.addedAt ?? .distantPast
            if ta != tb { return ta < tb }
            return a.sortName < b.sortName
        }
    }

    /// The place for something new: after everything else.
    public static func next(after orders: [Double?]) -> Double {
        (orders.compactMap { $0 }.max() ?? -1) + 1
    }

    /// The places after a drag moves the entry at `from` to `to` in a list of `count` entries in your order: every
    /// entry gets its new index, so the order sticks however it was before. Keyed by each entry's index before the
    /// move. Empty when nothing moves.
    public static func afterMove(count: Int, from: Int, to: Int) -> [Int: Double] {
        guard (0..<count).contains(from), (0..<count).contains(to), from != to else { return [:] }
        var order = Array(0..<count)
        order.remove(at: from)
        order.insert(from, at: to)
        var result: [Int: Double] = [:]
        for (place, index) in order.enumerated() { result[index] = Double(place) }
        return result
    }
}

/// Something the store remembers, for Past items: everything bought before, to tap onto a new list.
public struct PastItem<Ref> {
    public let ref: Ref
    public let name: String
    /// How many days it was bought on.
    public let timesBought: Int
    public let lastBought: Date?
    /// Due before the next trip (Restock).
    public let isRunningLow: Bool
    /// Bought on the last trip.
    public let boughtLastTrip: Bool
    public let isOnList: Bool

    public init(ref: Ref, name: String, timesBought: Int, lastBought: Date?, isRunningLow: Bool,
                boughtLastTrip: Bool, isOnList: Bool) {
        self.ref = ref
        self.name = name
        self.timesBought = timesBought
        self.lastBought = lastBought
        self.isRunningLow = isRunningLow
        self.boughtLastTrip = boughtLastTrip
        self.isOnList = isOnList
    }
}

/// The ways to look through Past items.
public enum PastItemsFilter: String, CaseIterable, Sendable {
    /// What you buy most, most first.
    case usual
    /// What Restock says will run out before the next trip.
    case runningLow
    /// What the last trip bought.
    case lastTrip
    /// Everything the store remembers, bought or not, by name.
    case alphabetical
}

public enum PastItems {
    /// `items` for `filter`, narrowed to names containing `query` (compared normalized; blank matches everything).
    /// Usual and Running low leave out what was never bought; A to Z keeps it.
    public static func filtered<Ref>(_ items: [PastItem<Ref>], by filter: PastItemsFilter,
                                     query: String = "") -> [PastItem<Ref>] {
        let key = ItemName.normalized(query)
        let matching = key.isEmpty ? items : items.filter { ItemName.normalized($0.name).contains(key) }
        let byName: (PastItem<Ref>, PastItem<Ref>) -> Bool = { a, b in
            let na = ItemName.normalized(a.name), nb = ItemName.normalized(b.name)
            return na != nb ? na < nb : a.name < b.name
        }
        let byUse: (PastItem<Ref>, PastItem<Ref>) -> Bool = { a, b in
            if a.timesBought != b.timesBought { return a.timesBought > b.timesBought }
            let la = a.lastBought ?? .distantPast, lb = b.lastBought ?? .distantPast
            if la != lb { return la > lb }
            return byName(a, b)
        }
        switch filter {
        case .usual: return matching.filter { $0.timesBought > 0 }.sorted(by: byUse)
        case .runningLow: return matching.filter { $0.isRunningLow }.sorted(by: byUse)
        case .lastTrip: return matching.filter { $0.boughtLastTrip }.sorted(by: byName)
        case .alphabetical: return matching.sorted(by: byName)
        }
    }

    /// The line under a past item: "Bought 14 times · last 9 days ago", "Bought once, yesterday", "Not bought yet".
    public static func summary<Ref>(_ item: PastItem<Ref>, now: Date, calendar: Calendar = .current) -> String {
        guard let last = item.lastBought, item.timesBought > 0 else { return "Not bought yet" }
        let ago = Restock.ago(last, now: now, calendar: calendar)
        if item.timesBought == 1 { return "Bought once, \(ago)" }
        return "Bought \(item.timesBought) times · last \(ago)"
    }
}
