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
}

extension ListSortable {
    public var learnedPosition: Double? { nil }
}

/// One heading of the list and its entries.
public struct ListSection<Entry> {
    public enum Kind: Hashable, Sendable {
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

/// The order the list is shown in. Unchecked entries come in the order the store is walked: by learned position,
/// then (for items not learned yet) their zone's average learned position, then their zone's place in the walking
/// order, then the entries without a zone at the end. Everything checked off comes last. Before anything is learned
/// that is simply the zones in walking order, alphabetical within a zone.
public enum ListOrdering {
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
                // Checked entries keep a stable alphabetical order; where they are in the store no longer matters.
                if !a.entry.isChecked {
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

    /// `entries` in list order under headings: a section for each run of entries in the same zone (titled from
    /// `zoneNames`), runs without a zone, then the checked-off ones. Before anything is learned that is one section
    /// per zone in walking order. Empty sections are left out. A zone index outside `zoneNames` counts as no zone.
    public static func sections<E: ListSortable>(_ entries: [E], zoneNames: [String],
                                                 zonePositions: [Int: Double] = [:]) -> [ListSection<E>] {
        var sections: [ListSection<E>] = []
        var seen: [ListSection<E>.Kind: Int] = [:]
        for entry in sorted(entries, zoneCount: zoneNames.count, zonePositions: zonePositions) {
            let kind: ListSection<E>.Kind
            if entry.isChecked {
                kind = .inCart
            } else if let z = entry.zoneIndex, zoneNames.indices.contains(z) {
                kind = .zone(z)
            } else {
                kind = .unzoned
            }
            if sections.last?.kind == kind {
                sections[sections.count - 1].entries.append(entry)
            } else {
                let title: String
                switch kind {
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

    /// Where in the walk an unchecked entry is expected: its learned position, its zone's average, or its zone's
    /// place in the walking order; nil (the end of the list) for an entry with none of those.
    static func walkPosition<E: ListSortable>(of entry: E, zoneCount: Int, zonePositions: [Int: Double]) -> Double? {
        if let learned = entry.learnedPosition { return min(max(learned, 0), 1) }
        guard let zone = entry.zoneIndex, zone >= 0, zone < zoneCount else { return nil }
        if let average = zonePositions[zone] { return average }
        return (Double(zone) + 0.5) / Double(zoneCount)
    }
}
