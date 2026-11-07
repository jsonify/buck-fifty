import Foundation

/// A hand-set answer to "does this item wander?" that beats what the trips say (issue #8).
public enum WanderOverride: String, Sendable, CaseIterable {
    /// "This moves around": always in Look for it.
    case wanders
    /// "This has a fixed spot": never in Look for it.
    case fixed
}

/// Some things never settle into one place in the store: the seasonal aisle, the treasure hunt on the centre tables.
/// Their samples jump around, so instead of dragging the sort about they're pinned to the top of the list under
/// "Look for it", with where they've been seen.
///
/// An item **wanders** once at least `minimumTrips` trips have placed it and its last `window` positions are spread
/// out (standard deviation over `spreadThreshold`) with fewer than half of them in one place (within `tolerance` of
/// each other). That keeps an item that simply moved, or one odd trip, out of it: four trips by the door and one at
/// the back is one place and a mistake, not wandering; two by the door then two at the back is a move. A wandering item still learns from every trip, and
/// goes back into the sort once its last `settleTrips` positions agree (within `tolerance`).
public struct Wandering: Sendable, Equatable {
    public var minimumTrips: Int
    public var spreadThreshold: Double
    public var window: Int
    public var settleTrips: Int
    public var tolerance: Double

    public init(minimumTrips: Int = 3, spreadThreshold: Double = 0.2, window: Int = 5, settleTrips: Int = 3,
                tolerance: Double = 0.15) {
        self.minimumTrips = minimumTrips
        self.spreadThreshold = spreadThreshold
        self.window = window
        self.settleTrips = settleTrips
        self.tolerance = tolerance
    }

    /// Whether an item with these recent positions (oldest first) wanders, given whether it was flagged before.
    public func isWandering(_ recent: [Double], wasWandering: Bool) -> Bool {
        if wasWandering { return !hasSettled(recent) }
        let latest = Array(recent.suffix(max(window, 1)))
        guard latest.count >= minimumTrips, let spread = LearnedPosition.spread(of: latest),
              spread > spreadThreshold else { return false }
        return Self.largestCluster(latest, within: tolerance) * 2 < latest.count
    }

    /// Whether the last `settleTrips` positions agree, within `tolerance` of each other.
    public func hasSettled(_ recent: [Double]) -> Bool {
        let last = recent.suffix(max(settleTrips, 1))
        guard last.count == max(settleTrips, 1), let low = last.min(), let high = last.max() else { return false }
        return high - low <= tolerance + 1e-9
    }

    /// The most samples that fit within `tolerance` of each other.
    public static func largestCluster(_ samples: [Double], within tolerance: Double) -> Int {
        let sorted = samples.sorted()
        var best = 0, start = 0
        for end in sorted.indices {
            while sorted[end] - sorted[start] > tolerance + 1e-9 { start += 1 }
            best = max(best, end - start + 1)
        }
        return best
    }

    /// Whether the item goes in Look for it: the hand-set answer if there is one, else what the trips say.
    public static func effective(learned: Bool, override: WanderOverride?) -> Bool {
        switch override {
        case .wanders: return true
        case .fixed: return false
        case nil: return learned
        }
    }

    /// Where a wandering item has been seen, for its row: "Seen anywhere from 20% to 75% of the way in, last at
    /// 40%". Nil with fewer than two positions (the item was flagged by hand before trips placed it).
    public func note(_ recent: [Double]) -> String? {
        let latest = recent.suffix(max(window, 1))
        guard latest.count >= 2, let low = latest.min(), let high = latest.max(), let last = latest.last else {
            return nil
        }
        let from = Self.percent(low), to = Self.percent(high)
        if from == to { return "Seen \(from)% of the way in" }
        return "Seen anywhere from \(from)% to \(to)% of the way in, last at \(Self.percent(last))%"
    }

    /// 0–1 as a whole percentage, to the nearest 5.
    static func percent(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 20).rounded()) * 5
    }
}
