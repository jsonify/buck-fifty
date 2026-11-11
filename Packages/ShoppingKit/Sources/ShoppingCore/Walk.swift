import Foundation

/// The list as a walk through the store (issue #25): its stops in walking order, each item's walk number, and which
/// stops are done, next or still ahead. The List, the Map and Home all show the same numbers and states.
///
/// The walk is worked out as if nothing were checked off, so an item keeps its place and its number through a trip:
/// checked items stay in their zone (struck through) instead of dropping to the end, and checking one off doesn't
/// renumber the rest.
public enum Walk {
    public enum StopState: Hashable, Sendable {
        /// Everything here is in the cart.
        case done
        /// The first stop in the walk with something still to get.
        case next
        /// Further on.
        case ahead
    }

    public enum StopKind: Hashable, Sendable {
        /// Unchecked things that move around: at the top, outside the walk.
        case lookForIt
        /// A run of the items in the zone at this index of the store's zones.
        case zone(Int)
        /// Items without a zone, at the end.
        case unzoned
    }

    /// A stop's identity, unique within a walk (a zone can come round twice).
    public struct StopID: Hashable, Sendable {
        public var kind: StopKind
        public var occurrence: Int
    }

    /// One stop of the walk: Look for it (things that move around, not numbered), a run of a zone's items, or the
    /// items without a zone.
    public struct Stop<Entry> {
        public var kind: StopKind
        public var title: String
        public var entries: [Entry]
        /// Each entry's walk number, from 1 at the door; nil under Look for it, which isn't in the walk.
        public var numbers: [Int?]
        public var occurrence: Int
        public var state: StopState
        /// How many entries here aren't checked off.
        public var left: Int

        public var id: StopID { StopID(kind: kind, occurrence: occurrence) }
        /// Whether the stop is part of the walk (everything but Look for it).
        public var isInWalk: Bool { kind != .lookForIt }
    }

    /// `entries` as stops in walking order (see `ListOrdering.sections`, which this follows with nothing checked off).
    public static func stops<E: ListSortable>(_ entries: [E], zoneNames: [String], zonePositions: [Int: Double] = [:],
                                              oneSectionPerZone: Bool = false) -> [Stop<E>] {
        let placed = entries.map(Unchecked.init)
        let sections = ListOrdering.sections(placed, zoneNames: zoneNames, zonePositions: zonePositions,
                                             oneSectionPerZone: oneSectionPerZone)
        var number = 0
        var foundNext = false
        return sections.map { section in
            let kind: StopKind
            switch section.kind {
            case .lookForIt: kind = .lookForIt
            case .zone(let index): kind = .zone(index)
            // Nothing is checked off here, so nothing is in the cart.
            case .unzoned, .inCart: kind = .unzoned
            }
            let originals = section.entries.map(\.entry)
            let numbers: [Int?] = originals.map { _ in
                guard kind != .lookForIt else { return nil }
                number += 1
                return number
            }
            let left = originals.filter { !$0.isChecked }.count
            let state: StopState
            if left == 0 {
                state = .done
            } else if kind != .lookForIt && !foundNext {
                state = .next
                foundNext = true
            } else {
                state = .ahead
            }
            return Stop(kind: kind, title: section.title, entries: originals, numbers: numbers,
                        occurrence: section.occurrence, state: state, left: left)
        }
    }

    /// The first thing still to get in the walk, and its number.
    public static func next<E: ListSortable>(in stops: [Stop<E>]) -> (entry: E, number: Int)? {
        for stop in stops where stop.isInWalk {
            for (entry, number) in zip(stop.entries, stop.numbers) where !entry.isChecked {
                if let number { return (entry, number) }
            }
        }
        return nil
    }

    /// An entry seen as not checked off, so it sorts into its place in the walk.
    private struct Unchecked<E: ListSortable>: ListSortable {
        let entry: E
        var sortName: String { entry.sortName }
        var zoneIndex: Int? { entry.zoneIndex }
        var isChecked: Bool { false }
        var learnedPosition: Double? { entry.learnedPosition }
        var isWandering: Bool { entry.isWandering }
    }
}
