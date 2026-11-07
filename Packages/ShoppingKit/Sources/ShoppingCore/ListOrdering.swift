import Foundation

/// What the list order needs to know about an entry.
public protocol ListSortable {
    /// The item's name.
    var sortName: String { get }
    /// The position of the item's zone in the store's walking order, or nil for an item without a zone.
    var zoneIndex: Int? { get }
    /// Whether the entry is checked off (in the cart).
    var isChecked: Bool { get }
    /// Where in a trip the item is grabbed, 0 (entrance) to 1 (checkout), learned from check-offs; nil until then.
    var learnedPosition: Double? { get }
    /// Whether the item never settles in one place (issue #8): it goes at the top, under Look for it.
    var isWandering: Bool { get }
}

extension ListSortable {
    public var learnedPosition: Double? { nil }
    public var isWandering: Bool { false }
}

/// One heading of the list and its entries.
public struct ListSection<Entry> {
    public enum Kind: Hashable, Sendable {
        /// Unchecked entries whose item wanders: at the top, to look out for.
        case lookForIt
        /// The entries in the zone at this index of the store's zones.
        case zone(Int)
        /// Entries whose item has no zone.
        case unzoned
        /// Checked-off entries.
        case inCart
    }

    /// Unique within a list: a zone can head two sections when an item has been learned somewhere else in the walk.
    public struct Key: Hashable, Sendable {
        public var kind: Kind
        /// 0 for the first section of this kind, 1 for the second…
        public var occurrence: Int
    }

    public var kind: Kind
    public var title: String
    public var entries: [Entry]
    public var occurrence: Int = 0

    public var id: Key { Key(kind: kind, occurrence: occurrence) }
}

/// The order the list is shown in. Unchecked items that wander come first (alphabetically: they could be anywhere).
/// The other unchecked entries come in the order the store is walked: by learned position,
/// then (for items not learned yet) their zone's average learned position, then their zone's place in the walking
/// order, then the entries without a zone at the end. Everything checked off comes last. Before anything is learned
/// that is simply the zones in walking order, alphabetical within a zone.
public enum ListOrdering {
    public static let lookForItTitle = "Look for it"
    public static let unzonedTitle = "No zone yet"
    public static let inCartTitle = "In the cart"

    /// The average learned position of each zone's items, by zone index (zones with nothing learned are left out).
    public static func zoneAverages(_ items: [(zone: Int?, position: Double?)]) -> [Int: Double] {
        var sums: [Int: (total: Double, count: Int)] = [:]
        for item in items {
            guard let zone = item.zone, let position = item.position else { continue }
            let sum = sums[zone] ?? (0, 0)
            sums[zone] = (sum.total + position, sum.count + 1)
        }
        return sums.mapValues { $0.total / Double($0.count) }
    }

    /// `entries` in list order, without headings. `zoneCount` is how many zones the store has (zone indexes outside
    /// it count as no zone; by default every zone index counts) and `zonePositions` their average learned positions.
    public static func sorted<E: ListSortable>(_ entries: [E], zoneCount: Int? = nil,
                                               zonePositions: [Int: Double] = [:]) -> [E] {
        let zones = zoneCount ?? ((entries.compactMap(\.zoneIndex).max() ?? -1) + 1)
        return entries.map { (entry: $0, key: walkPosition(of: $0, zoneCount: zones, zonePositions: zonePositions)) }
            .sorted { a, b in
                if a.entry.isChecked != b.entry.isChecked { return !a.entry.isChecked }
                let wa = !a.entry.isChecked && a.entry.isWandering, wb = !b.entry.isChecked && b.entry.isWandering
                if wa != wb { return wa }
                // Checked entries keep a stable alphabetical order; where they are in the store no longer matters.
                // So do wandering ones: they could be anywhere.
                if !a.entry.isChecked && !wa {
                    switch (a.key, b.key) {
                    case let (ka?, kb?) where ka != kb: return ka < kb
                    case (.some, .none): return true
                    case (.none, .some): return false
                    default: break
                    }
                    let za = a.entry.zoneIndex ?? Int.max, zb = b.entry.zoneIndex ?? Int.max
                    if za != zb { return za < zb }
                }
                let na = ItemName.normalized(a.entry.sortName), nb = ItemName.normalized(b.entry.sortName)
                if na != nb { return na < nb }
                return a.entry.sortName < b.entry.sortName
            }
            .map { $0.entry }
    }

    /// `entries` in list order under headings: Look for it (the unchecked ones that wander), a section for each run
    /// of entries in the same zone (titled from `zoneNames`), runs without a zone, then the checked-off ones. Before anything is learned that is one section
    /// per zone in walking order. Empty sections are left out. A zone index outside `zoneNames` counts as no zone.
    ///
    /// With `oneSectionPerZone` (the list at home, when it's read rather than walked), a zone that comes round again
    /// later in the walk doesn't get a second heading: its entries join its first section, still in walk order.
    public static func sections<E: ListSortable>(_ entries: [E], zoneNames: [String],
                                                 zonePositions: [Int: Double] = [:],
                                                 oneSectionPerZone: Bool = false) -> [ListSection<E>] {
        var sections: [ListSection<E>] = []
        var seen: [ListSection<E>.Kind: Int] = [:]
        for entry in sorted(entries, zoneCount: zoneNames.count, zonePositions: zonePositions) {
            let kind: ListSection<E>.Kind
            if entry.isChecked {
                kind = .inCart
            } else if entry.isWandering {
                kind = .lookForIt
            } else if let z = entry.zoneIndex, zoneNames.indices.contains(z) {
                kind = .zone(z)
            } else {
                kind = .unzoned
            }
            if sections.last?.kind == kind {
                sections[sections.count - 1].entries.append(entry)
            } else if oneSectionPerZone, let index = sections.firstIndex(where: { $0.kind == kind }) {
                sections[index].entries.append(entry)
            } else {
                let title: String
                switch kind {
                case .lookForIt: title = lookForItTitle
                case .zone(let z): title = zoneNames[z]
                case .unzoned: title = unzonedTitle
                case .inCart: title = inCartTitle
                }
                let occurrence = seen[kind, default: 0]
                seen[kind] = occurrence + 1
                sections.append(ListSection(kind: kind, title: title, entries: [entry], occurrence: occurrence))
            }
        }
        return sections
    }

    /// New learned positions after a drag moves the unchecked entry at `from` to `to`. `keys` are the unchecked
    /// entries' walk positions in list order (`walkPosition`, nil for the entries at the end with none). Returns the
    /// position to give each entry that needs one, by its index in `keys`: the moved entry lands between its new
    /// neighbours. When those neighbours share a position (items placed only by their zone), the whole tie gets
    /// spread out, so the order sticks.
    public static func positionsAfterMove(_ keys: [Double?], from: Int, to: Int) -> [Int: Double] {
        guard keys.indices.contains(from), keys.indices.contains(to), from != to else { return [:] }
        var order = Array(keys.indices)
        order.remove(at: from)
        order.insert(from, at: to)
        /// The key of the entry at `index` of the new order (nil for the moved entry and those without one).
        func key(_ index: Int) -> Double? { order[index] == from ? nil : keys[order[index]] }
        func spread(_ range: ClosedRange<Int>, above low: Double, below high: Double) -> [Int: Double] {
            var result: [Int: Double] = [:]
            let step = (high - low) / Double(range.count + 1)
            for (n, index) in range.enumerated() { result[order[index]] = low + step * Double(n + 1) }
            return result
        }

        // Dropped among the entries at the end that have no position: they get positions up to the moved one.
        if to > 0, key(to - 1) == nil {
            var first = to - 1
            while first > 0, key(first - 1) == nil { first -= 1 }
            let low = first > 0 ? key(first - 1) ?? 0 : 0
            return spread(first...to, above: low, below: 1)
        }
        let low = to > 0 ? key(to - 1) ?? 0 : 0
        let high = to + 1 < order.count ? key(to + 1) ?? 1 : 1
        if low < high { return [from: (low + high) / 2] }

        // A tie: spread every entry at that position (the moved one among them) between the positions either side.
        let tied = low
        var first = to, last = to
        while first > 0, key(first - 1) == tied { first -= 1 }
        while last + 1 < order.count, key(last + 1) == tied { last += 1 }
        let below = first > 0 ? key(first - 1) ?? 0 : min(0, tied)
        let above = last + 1 < order.count ? key(last + 1) ?? 1 : max(1, tied)
        return spread(first...last, above: below, below: above)
    }

    /// The walk positions of `entries`, as `sorted` uses them (see `positionsAfterMove`). Leave out wandering
    /// entries: they're not in the walk, so their positions would be out of order.
    public static func walkPositions<E: ListSortable>(_ entries: [E], zoneCount: Int,
                                                      zonePositions: [Int: Double]) -> [Double?] {
        entries.map { walkPosition(of: $0, zoneCount: zoneCount, zonePositions: zonePositions) }
    }

    /// Where in the walk an unchecked entry is expected: its learned position, its zone's average, or its zone's
    /// place in the walking order; nil (the end of the list) for an entry with none of those.
    static func walkPosition<E: ListSortable>(of entry: E, zoneCount: Int, zonePositions: [Int: Double]) -> Double? {
        if let learned = entry.learnedPosition { return min(max(learned, 0), 1) }
        guard let zone = entry.zoneIndex, zone >= 0, zone < zoneCount else { return nil }
        if let average = zonePositions[zone] { return average }
        return (Double(zone) + 0.5) / Double(zoneCount)
    }
}
