import Foundation

/// A point in a store, in metres from the entrance: x east, y north (magnetic), so every trip shares one frame.
public struct FloorPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let entrance = FloorPoint(x: 0, y: 0)

    public static func + (a: FloorPoint, b: FloorPoint) -> FloorPoint { FloorPoint(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: FloorPoint, b: FloorPoint) -> FloorPoint { FloorPoint(x: a.x - b.x, y: a.y - b.y) }
    public static func * (a: FloorPoint, k: Double) -> FloorPoint { FloorPoint(x: a.x * k, y: a.y * k) }

    public func distance(to other: FloorPoint) -> Double {
        let d = self - other
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    /// The point turned so that compass heading `degrees` points along +y (up the floor plan). Store aisles run on a
    /// grid; turning by the grid's heading lines them up with the screen.
    public func rotated(toHeading degrees: Double) -> FloorPoint {
        let g = degrees * .pi / 180
        return FloorPoint(x: x * cos(g) - y * sin(g), y: x * sin(g) + y * cos(g))
    }
}

/// Pedestrian dead reckoning (issue #5): from the door, each stretch walked moves the point by its distance along the
/// heading, x += d·sin θ, y += d·cos θ. Steel shelving bends magnetic headings, but aisles run on a grid, so a heading
/// near one of the grid's four directions is snapped to it.
public struct DeadReckoning: Sendable, Equatable {
    public private(set) var position: FloorPoint
    /// The compass heading of the store's aisles (degrees), once known; nil walks the raw heading.
    public var gridHeading: Double?
    /// How close (degrees) a heading must be to a grid direction to snap to it.
    public var snapTolerance: Double

    public init(gridHeading: Double? = nil, snapTolerance: Double = 25, position: FloorPoint = .entrance) {
        self.gridHeading = gridHeading
        self.snapTolerance = snapTolerance
        self.position = position
    }

    /// The heading to walk along for a measured `heading` (degrees): the nearest grid direction when within
    /// `snapTolerance`, otherwise the heading itself.
    public func walkingHeading(_ heading: Double) -> Double {
        guard let grid = gridHeading else { return Self.normalized(heading) }
        let offset = Self.signedDifference(heading, grid)
        let quarter = (offset / 90).rounded()
        guard abs(offset - quarter * 90) <= snapTolerance else { return Self.normalized(heading) }
        return Self.normalized(grid + quarter * 90)
    }

    /// Walks `distance` metres along `heading` and returns the new position.
    @discardableResult
    public mutating func walk(_ distance: Double, heading: Double) -> FloorPoint {
        guard distance > 0 else { return position }
        let h = walkingHeading(heading) * .pi / 180
        position = FloorPoint(x: position.x + distance * sin(h), y: position.y + distance * cos(h))
        return position
    }

    /// The average of compass headings (degrees), across the 359 → 0 wrap; nil for none.
    public static func meanHeading(_ headings: [Double]) -> Double? {
        guard !headings.isEmpty else { return nil }
        let s = headings.reduce(0) { $0 + sin($1 * .pi / 180) }
        let c = headings.reduce(0) { $0 + cos($1 * .pi / 180) }
        guard abs(s) > 1e-9 || abs(c) > 1e-9 else { return nil }
        return normalized(atan2(s, c) * 180 / .pi)
    }

    /// `a − b` in degrees, in −180..<180.
    public static func signedDifference(_ a: Double, _ b: Double) -> Double {
        let d = normalized(a - b)
        return d >= 180 ? d - 360 : d
    }

    /// Degrees in 0..<360.
    public static func normalized(_ degrees: Double) -> Double {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }
}

/// Correcting a dead-reckoned path. Some of its points are known: the door it started at, items whose spot is
/// already settled (landmarks), the checkout it ended at. The error at each known point is spread back along the path
/// to the one before it.
public enum PathCorrection {
    /// `path` with its drift taken out. `anchors` maps indices of `path` to where those points really are. The start
    /// is an anchor at its own place unless given. Between anchors the correction changes in step with the index;
    /// after the last one it stays as it was there.
    public static func corrected(_ path: [FloorPoint], anchors: [Int: FloorPoint]) -> [FloorPoint] {
        guard !path.isEmpty else { return [] }
        var fixes: [(index: Int, offset: FloorPoint)] = anchors
            .filter { path.indices.contains($0.key) }
            .map { (index: $0.key, offset: $0.value - path[$0.key]) }
            .sorted { $0.index < $1.index }
        if fixes.first?.index != 0 { fixes.insert((index: 0, offset: FloorPoint(x: 0, y: 0)), at: 0) }
        var result = path
        for (i, point) in path.enumerated() {
            let next = fixes.firstIndex { $0.index >= i } ?? fixes.count
            let offset: FloorPoint
            if next == fixes.count {
                offset = fixes[fixes.count - 1].offset
            } else if fixes[next].index == i || next == 0 {
                offset = fixes[next].offset
            } else {
                let a = fixes[next - 1], b = fixes[next]
                let t = Double(i - a.index) / Double(b.index - a.index)
                offset = a.offset + (b.offset - a.offset) * t
            }
            result[i] = point + offset
        }
        return result
    }

    /// The correction in force after the last anchor (what to add to a live point), or zero.
    public static func currentOffset(_ path: [FloorPoint], anchors: [Int: FloorPoint]) -> FloorPoint {
        guard let last = anchors.filter({ path.indices.contains($0.key) }).max(by: { $0.key < $1.key }) else {
            return FloorPoint(x: 0, y: 0)
        }
        return last.value - path[last.key]
    }
}

/// Spots on the floor plan from many trips' points.
public enum FloorPlan {
    /// How many recent points an item's spot is worked out from.
    public static let recentPoints = 10

    /// A robust average: the median of the xs and of the ys. Nil for no points.
    public static func median(_ points: [FloorPoint]) -> FloorPoint? {
        guard !points.isEmpty else { return nil }
        func mid(_ values: [Double]) -> Double {
            let v = values.sorted()
            return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
        }
        return FloorPoint(x: mid(points.map(\.x)), y: mid(points.map(\.y)))
    }

    /// The spot of an item seen at `points`, if it has settled: at least `minimumCount` points, most of them (by
    /// median distance) within `maxSpread` metres of their median. Checking off a landmark snaps the trip to it.
    public static func landmark(_ points: [FloorPoint], minimumCount: Int = 3, maxSpread: Double = 4) -> FloorPoint? {
        guard points.count >= minimumCount, let center = median(points) else { return nil }
        let distances = points.map { $0.distance(to: center) }.sorted()
        let spread = distances.count % 2 == 1 ? distances[distances.count / 2]
            : (distances[distances.count / 2 - 1] + distances[distances.count / 2]) / 2
        return spread <= maxSpread ? center : nil
    }

    /// `path` without points closer than `minimumGap` metres to the last one kept (the last point is always kept).
    public static func thinned(_ path: [FloorPoint], minimumGap: Double = 1.5) -> [FloorPoint] {
        guard var kept = path.first.map({ [$0] }) else { return [] }
        for point in path.dropFirst() where point.distance(to: kept[kept.count - 1]) >= minimumGap {
            kept.append(point)
        }
        if let last = path.last, kept[kept.count - 1] != last { kept.append(last) }
        return kept
    }

    /// A path as stored text ("1.5,2.0;3.0,4.5").
    public static func encode(_ path: [FloorPoint]) -> String? {
        path.isEmpty ? nil : path.map { String(format: "%.1f,%.1f", $0.x, $0.y) }.joined(separator: ";")
    }

    /// A path read back from `encode`'s text; unreadable points are skipped.
    public static func decode(_ text: String?) -> [FloorPoint] {
        (text ?? "").split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: ",")
            guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
            return FloorPoint(x: x, y: y)
        }
    }
}
