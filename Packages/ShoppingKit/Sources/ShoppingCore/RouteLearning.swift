import Foundation

/// One check-off on a trip's route: which item, and when.
public struct RouteStop<ItemID: Hashable>: Equatable {
    public var item: ItemID
    public var time: Date

    public init(item: ItemID, time: Date) {
        self.item = item
        self.time = time
    }
}

/// What a store has learned about where one item is: a position from 0 (the entrance) to 1 (the checkout), how many
/// trips taught it, and the most recent samples (the spread matters to wandering items, issue #8).
public struct LearnedPosition: Sendable, Equatable {
    public var position: Double?
    public var sampleCount: Int
    /// The latest samples, oldest first.
    public var recent: [Double]

    public init(position: Double? = nil, sampleCount: Int = 0, recent: [Double] = []) {
        self.position = position
        self.sampleCount = sampleCount
        self.recent = recent
    }

    /// The standard deviation of the recent samples, or nil with fewer than two.
    public var spread: Double? { Self.spread(of: recent) }

    /// The standard deviation of `samples`, or nil with fewer than two.
    public static func spread(of samples: [Double]) -> Double? {
        guard samples.count >= 2 else { return nil }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count)
        return variance.squareRoot()
    }

    /// The recent samples as stored text ("0.250,0.800").
    public static func encode(_ samples: [Double]) -> String? {
        samples.isEmpty ? nil : samples.map { String(format: "%.3f", $0) }.joined(separator: ",")
    }

    /// Samples read back from `encode`'s text; anything unreadable is skipped.
    public static func decode(_ text: String?) -> [Double] {
        (text ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// Your check-offs are the map: the order you check things off in is your route through the store. When a trip ends,
/// each item checked off on it gets a sample, where in the trip it was grabbed (0 = entrance, 1 = checkout), and its
/// learned position moves toward it. Sorting the list by learned position puts it in the order you walk.
public struct RouteLearning: Sendable, Equatable {
    /// How far a position moves toward each new sample (an exponential moving average), so old trips are forgotten.
    public var smoothing: Double
    /// How many recent samples an item keeps.
    public var sampleLimit: Int
    /// Check-offs closer together than this at the end of a trip are a burst ("check everything at the checkout").
    public var burstGap: TimeInterval
    /// How many check-offs in a row make a burst; two things off the same shelf a second apart are not one.
    public var minimumBurst: Int
    /// When this many trips in a row agree on a new place (within `moveTolerance` of each other) and the moving
    /// average still lags behind them, the item has moved: its position jumps to where those trips found it. The
    /// average alone would take many trips to follow when the coffee moves across the store.
    public var moveAfter: Int
    public var moveTolerance: Double

    public init(smoothing: Double = 0.4, sampleLimit: Int = 10, burstGap: TimeInterval = 2, minimumBurst: Int = 3,
                moveAfter: Int = 2, moveTolerance: Double = 0.15) {
        self.smoothing = smoothing
        self.sampleLimit = sampleLimit
        self.burstGap = burstGap
        self.minimumBurst = minimumBurst
        self.moveAfter = moveAfter
        self.moveTolerance = moveTolerance
    }

    /// The check-offs that teach something: in time order, each item once (its first check-off), without a burst at
    /// the end of the trip.
    public func usableStops<ID: Hashable>(_ stops: [RouteStop<ID>]) -> [RouteStop<ID>] {
        let ordered = stops.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
        var seen = Set<ID>()
        var unique = ordered.filter { seen.insert($0.item).inserted }
        guard !unique.isEmpty else { return [] }
        var burstStart = unique.count - 1
        while burstStart > 0, unique[burstStart].time.timeIntervalSince(unique[burstStart - 1].time) < burstGap {
            burstStart -= 1
        }
        let burst = unique.count - burstStart
        if burst >= minimumBurst { unique.removeLast(burst) }
        return unique
    }

    /// Where in the trip each item was grabbed, by rank: the k-th of n usable check-offs is at k / (n − 1), so a long
    /// chat in the bakery doesn't skew anything. Empty for a trip with fewer than two usable check-offs.
    public func rankPositions<ID: Hashable>(_ stops: [RouteStop<ID>]) -> [ID: Double] {
        let usable = usableStops(stops)
        guard usable.count >= 2 else { return [:] }
        var positions: [ID: Double] = [:]
        for (rank, stop) in usable.enumerated() {
            positions[stop.item] = Double(rank) / Double(usable.count - 1)
        }
        return positions
    }

    /// The same by time: (t − first) / (last − first). Kept alongside the rank version to compare on real trips.
    public func timePositions<ID: Hashable>(_ stops: [RouteStop<ID>]) -> [ID: Double] {
        let usable = usableStops(stops)
        guard usable.count >= 2, let first = usable.first?.time, let last = usable.last?.time else { return [:] }
        let span = last.timeIntervalSince(first)
        guard span > 0 else { return [:] }
        var positions: [ID: Double] = [:]
        for stop in usable {
            positions[stop.item] = stop.time.timeIntervalSince(first) / span
        }
        return positions
    }

    /// `current` moved toward `sample` by `smoothing` (or `sample` itself when there's nothing yet).
    public func smoothed(_ current: Double?, with sample: Double) -> Double {
        let p = Self.clamped(sample)
        guard let current else { return p }
        return current + smoothing * (p - current)
    }

    /// What an item has learned once a trip found it at `sample`.
    public func updated(_ current: LearnedPosition, with sample: Double) -> LearnedPosition {
        let p = Self.clamped(sample)
        var next = current
        next.sampleCount = current.sampleCount + 1
        next.recent = Array((current.recent + [p]).suffix(max(sampleLimit, 1)))
        var position = smoothed(current.position, with: p)
        let lastFew = next.recent.suffix(moveAfter)
        if current.position != nil, moveAfter > 0, lastFew.count == moveAfter,
           let low = lastFew.min(), let high = lastFew.max(), high - low <= moveTolerance {
            let mean = lastFew.reduce(0, +) / Double(lastFew.count)
            if abs(mean - position) > moveTolerance { position = mean }
        }
        next.position = position
        return next
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
