import Foundation

/// What the list order needs to know about an entry.
public protocol ListSortable {
    /// The item's name.
    var sortName: String { get }
    /// The position of the item's zone in the store's walking order, or nil for an item without a zone.
    var zoneIndex: Int? { get }
    /// Whether the entry is checked off (in the cart).
    var isChecked: Bool { get }
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

    public var kind: Kind
    public var title: String
    public var entries: [Entry]
}

/// The order the list is shown in. Until positions are learned from check-offs, unchecked entries are grouped by
/// zone in walking order (alphabetical within a zone), then the entries without a zone, then everything checked off.
public enum ListOrdering {
    public static let unzonedTitle = "No zone yet"
    public static let inCartTitle = "In the cart"

    /// `entries` in list order, without headings.
    public static func sorted<E: ListSortable>(_ entries: [E]) -> [E] {
        entries.sorted { a, b in
            if a.isChecked != b.isChecked { return !a.isChecked }
            // Checked entries keep a stable alphabetical order; their zone no longer matters.
            if !a.isChecked {
                let za = a.zoneIndex ?? Int.max, zb = b.zoneIndex ?? Int.max
                if za != zb { return za < zb }
            }
            let na = ItemName.normalized(a.sortName), nb = ItemName.normalized(b.sortName)
            if na != nb { return na < nb }
            return a.sortName < b.sortName
        }
    }

    /// `entries` in list order under headings: a section per zone that has entries (titled from `zoneNames`), then
    /// the entries without a zone, then the checked-off ones. Empty sections are left out. A zone index outside
    /// `zoneNames` counts as no zone.
    public static func sections<E: ListSortable>(_ entries: [E], zoneNames: [String]) -> [ListSection<E>] {
        var sections: [ListSection<E>] = []
        for entry in sorted(entries) {
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
                sections.append(ListSection(kind: kind, title: title, entries: [entry]))
            }
        }
        return sections
    }
}
