import Foundation

/// A rectangle on a floor plan drawing, in whatever units the caller uses (fractions of the plan, or points).
public struct PlanRect: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(_ px: Double, _ py: Double) -> Bool {
        px >= x && px <= x + width && py >= y && py <= y + height
    }

    /// How far a point is from the rectangle (0 inside).
    public func distance(to px: Double, _ py: Double) -> Double {
        let dx = max(x - px, 0, px - (x + width))
        let dy = max(y - py, 0, py - (y + height))
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The rectangle scaled from fractions of a plan to a `width` × `height` drawing.
    public func scaled(width w: Double, height h: Double) -> PlanRect {
        PlanRect(x: x * w, y: y * h, width: width * w, height: height * h)
    }
}

/// One department block of a store's floor plan drawing, and the zone it belongs to (nil for places that aren't
/// shopped, like the restrooms). Positions are fractions of the plan: x across, y down, the front of the store at the
/// bottom as drawn.
public struct PlanBlock: Sendable, Hashable {
    public var label: String
    public var zone: String?
    public var rect: PlanRect

    public init(_ label: String, zone: String?, x: Double, y: Double, width: Double, height: Double) {
        self.label = label
        self.zone = zone
        rect = PlanRect(x: x, y: y, width: width, height: height)
    }
}

/// A point on a floor plan drawing, as fractions of the plan: x across, y down.
public struct PlanPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// The point kept on the plan (0...1 both ways).
    public var clamped: PlanPoint { PlanPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1)) }

    /// A point tapped on the `upright` drawing, back on the plan as drawn (the quarter turn undone).
    public static func fromUpright(x: Double, y: Double) -> PlanPoint { PlanPoint(x: y, y: 1 - x) }

    /// The point on the `upright` drawing.
    public var upright: PlanPoint { PlanPoint(x: 1 - y, y: x) }
}

/// A store's floor plan drawing: its blocks, where the entrance and the exit are, and its shape (width over height).
public struct PlanDrawing: Sendable, Hashable {
    public var aspect: Double
    public var blocks: [PlanBlock]
    /// The entrance, as fractions of the plan.
    public var entranceX: Double
    public var entranceY: Double
    /// The way out, as fractions of the plan: the entrance unless the store says otherwise.
    public var exitX: Double
    public var exitY: Double

    public init(aspect: Double, blocks: [PlanBlock], entranceX: Double, entranceY: Double,
                exitX: Double? = nil, exitY: Double? = nil) {
        self.aspect = aspect
        self.blocks = blocks
        self.entranceX = entranceX
        self.entranceY = entranceY
        self.exitX = exitX ?? entranceX
        self.exitY = exitY ?? entranceY
    }

    public var entrance: PlanPoint { PlanPoint(x: entranceX, y: entranceY) }
    public var exit: PlanPoint { PlanPoint(x: exitX, y: exitY) }

    /// The drawing with the store's own entrance and exit where it has them (set by tapping the map).
    public func withDoors(entrance: PlanPoint?, exit: PlanPoint?) -> PlanDrawing {
        var drawing = self
        if let entrance { (drawing.entranceX, drawing.entranceY) = (entrance.x, entrance.y) }
        if let exit { (drawing.exitX, drawing.exitY) = (exit.x, exit.y) }
        return drawing
    }

    /// The zones the drawing shows.
    public var zones: Set<String> { Set(blocks.compactMap(\.zone)) }

    /// The drawing turned a quarter turn clockwise, so a wide warehouse fills a phone held upright: what was along the
    /// bottom (the front) runs up the left side.
    public var upright: PlanDrawing {
        PlanDrawing(aspect: 1 / aspect,
                    blocks: blocks.map { block in
                        var turned = block
                        turned.rect = PlanRect(x: 1 - block.rect.y - block.rect.height, y: block.rect.x,
                                               width: block.rect.height, height: block.rect.width)
                        return turned
                    },
                    entranceX: 1 - entranceY, entranceY: entranceX, exitX: 1 - exitY, exitY: exitX)
    }

    /// The middle of each zone's biggest block, keyed by the zone's normalized name: where its pin goes, and where a
    /// walk through the store stops for it.
    public var zoneCenters: [String: PlanPoint] {
        var biggest: [String: PlanRect] = [:]
        for block in blocks {
            guard let zone = block.zone else { continue }
            let key = ItemName.normalized(zone)
            if let rect = biggest[key], rect.width * rect.height >= block.rect.width * block.rect.height { continue }
            biggest[key] = block.rect
        }
        return biggest.mapValues { PlanPoint(x: $0.x + $0.width / 2, y: $0.y + $0.height / 2) }
    }

    /// `zoneNames` in the order a short walk visits them, in from the entrance and out at the exit: each zone at the
    /// middle of its biggest block, the walk's length measured on the plan's real shape. Zones the drawing doesn't
    /// show keep their place after the zone they followed before. It's a starting point; the trips refine it.
    public func walkingOrder(of zoneNames: [String]) -> [String] {
        let centers = zoneCenters
        let onPlan = zoneNames.filter { centers[ItemName.normalized($0)] != nil }
        guard onPlan.count > 1 else { return zoneNames }
        func point(_ name: String) -> PlanPoint { centers[ItemName.normalized(name)]! }
        func distance(_ a: PlanPoint, _ b: PlanPoint) -> Double {
            let dx = (a.x - b.x) * aspect, dy = a.y - b.y
            return (dx * dx + dy * dy).squareRoot()
        }
        // Nearest first from the entrance…
        var route: [String] = []
        var left = onPlan
        var here = entrance
        while !left.isEmpty {
            let next = left.indices.min { distance(here, point(left[$0])) < distance(here, point(left[$1])) }!
            here = point(left[next])
            route.append(left.remove(at: next))
        }
        // …then untangled: reverse any stretch that makes the walk, door to door, shorter.
        func stop(_ i: Int) -> PlanPoint { i < 0 ? entrance : i >= route.count ? exit : point(route[i]) }
        var improved = true
        var passes = 0
        while improved, passes < 50 {
            improved = false
            passes += 1
            for i in 0..<(route.count - 1) {
                for j in (i + 1)..<route.count {
                    let before = distance(stop(i - 1), stop(i)) + distance(stop(j), stop(j + 1))
                    let after = distance(stop(i - 1), stop(j)) + distance(stop(i), stop(j + 1))
                    if after < before - 1e-9 {
                        route[i...j].reverse()
                        improved = true
                    }
                }
            }
        }
        // The zones not on the drawing, each after the zone it followed.
        var result = route
        for (index, name) in zoneNames.enumerated() where centers[ItemName.normalized(name)] == nil {
            if index == 0 {
                result.insert(name, at: 0)
            } else if let after = result.firstIndex(of: zoneNames[index - 1]) {
                result.insert(name, at: after + 1)
            } else {
                result.append(name)
            }
        }
        return result
    }

    /// The block under a tap at (`x`, `y`) on a `width` × `height` drawing: the smallest block containing it, or else
    /// the nearest block within `tolerance` (thin strips along the walls are hard to hit). Only blocks with a zone
    /// count.
    public func block(atX x: Double, y: Double, width: Double, height: Double, tolerance: Double = 18) -> PlanBlock? {
        let zoned = blocks.filter { $0.zone != nil }
        let rects = zoned.map { $0.rect.scaled(width: width, height: height) }
        let inside = rects.indices.filter { rects[$0].contains(x, y) }
        if let smallest = inside.min(by: { rects[$0].width * rects[$0].height < rects[$1].width * rects[$1].height }) {
            return zoned[smallest]
        }
        let nearest = rects.indices.min { rects[$0].distance(to: x, y) < rects[$1].distance(to: x, y) }
        guard let nearest, rects[nearest].distance(to: x, y) <= tolerance else { return nil }
        return zoned[nearest]
    }
}

extension DefaultZones {
    /// The Aurora Village Costco's floor plan, from the owner's drawing (each department block and its zone).
    public static let costcoAuroraVillagePlan = PlanDrawing(aspect: 2.109, blocks: [
        PlanBlock("Soda", zone: "Beverages, soda & Gatorade", x: 0.151, y: 0.008, width: 0.257, height: 0.019),
        PlanBlock("Gatorade", zone: "Beverages, soda & Gatorade", x: 0.408, y: 0.008, width: 0.122, height: 0.019),
        PlanBlock("Snacks", zone: "Snacks (top wall)", x: 0.530, y: 0.008, width: 0.218, height: 0.019),
        PlanBlock("Pharmacy", zone: "Medicine & pharmacy", x: 0.748, y: 0.008, width: 0.109, height: 0.019),
        PlanBlock("Hearing", zone: nil, x: 0.858, y: 0.008, width: 0.062, height: 0.019),
        PlanBlock("Skincare", zone: "Medicine & pharmacy", x: 0.759, y: 0.253, width: 0.122, height: 0.025),
        PlanBlock("Pets", zone: "Laundry, cleaning & pet", x: 0.011, y: 0.068, width: 0.041, height: 0.196),
        PlanBlock("Water", zone: "Paper goods & water", x: 0.011, y: 0.306, width: 0.029, height: 0.071),
        PlanBlock("Paper towels", zone: "Paper goods & water", x: 0.061, y: 0.319, width: 0.063, height: 0.112),
        PlanBlock("Laundry", zone: "Laundry, cleaning & pet", x: 0.070, y: 0.073, width: 0.076, height: 0.187),
        PlanBlock("Beverages", zone: "Beverages, soda & Gatorade", x: 0.153, y: 0.047, width: 0.082, height: 0.187),
        PlanBlock("Frozen", zone: "Frozen", x: 0.256, y: 0.053, width: 0.104, height: 0.217),
        PlanBlock("Pantry", zone: "Pantry", x: 0.460, y: 0.042, width: 0.289, height: 0.217),
        PlanBlock("Medicine", zone: "Medicine & pharmacy", x: 0.762, y: 0.042, width: 0.122, height: 0.196),
        PlanBlock("Restrooms", zone: nil, x: 0.939, y: 0.015, width: 0.061, height: 0.235),
        PlanBlock("Pick-up", zone: nil, x: 0.941, y: 0.238, width: 0.056, height: 0.111),
        PlanBlock("Deli", zone: "Rotisserie & deli", x: 0.151, y: 0.463, width: 0.047, height: 0.045),
        PlanBlock("Rotisserie", zone: "Rotisserie & deli", x: 0.151, y: 0.515, width: 0.047, height: 0.065),
        PlanBlock("Meat counter", zone: "Meat", x: 0.151, y: 0.585, width: 0.047, height: 0.187),
        PlanBlock("Bakery", zone: "Bakery", x: 0.151, y: 0.779, width: 0.047, height: 0.082),
        PlanBlock("Coolers", zone: "Dairy & center coolers", x: 0.211, y: 0.296, width: 0.143, height: 0.185),
        PlanBlock("Meat", zone: "Meat", x: 0.211, y: 0.498, width: 0.143, height: 0.142),
        PlanBlock("Baked goods", zone: "Bakery", x: 0.213, y: 0.678, width: 0.057, height: 0.167),
        PlanBlock("Produce", zone: "Produce", x: 0.281, y: 0.678, width: 0.069, height: 0.167),
        PlanBlock("Adult bev.", zone: "Adult beverages", x: 0.361, y: 0.678, width: 0.041, height: 0.280),
        PlanBlock("Cold produce", zone: "Produce", x: 0.207, y: 0.876, width: 0.146, height: 0.112),
        PlanBlock("Dairy", zone: "Dairy & center coolers", x: 0.145, y: 0.298, width: 0.058, height: 0.133),
        PlanBlock("Seasonal", zone: "Snacks, clothing & seasonal", x: 0.368, y: 0.306, width: 0.181, height: 0.344),
        PlanBlock("Clothing", zone: "Snacks, clothing & seasonal", x: 0.561, y: 0.299, width: 0.093, height: 0.345),
        PlanBlock("Snacks", zone: "Snacks, clothing & seasonal", x: 0.672, y: 0.301, width: 0.174, height: 0.344),
        PlanBlock("Small appliances", zone: "Appliances", x: 0.522, y: 0.678, width: 0.131, height: 0.276),
        PlanBlock("Electronics", zone: "Electronics & optical", x: 0.664, y: 0.678, width: 0.140, height: 0.276),
        PlanBlock("TVs", zone: "Electronics & optical", x: 0.816, y: 0.846, width: 0.067, height: 0.054),
        PlanBlock("Optical", zone: "Electronics & optical", x: 0.816, y: 0.922, width: 0.067, height: 0.068),
        PlanBlock("Self checkout", zone: "Checkout", x: 0.883, y: 0.300, width: 0.034, height: 0.066),
        PlanBlock("Checkout", zone: "Checkout", x: 0.883, y: 0.374, width: 0.043, height: 0.244),
        PlanBlock("Food court", zone: "Food court", x: 0.949, y: 0.377, width: 0.040, height: 0.112),
        PlanBlock("Service", zone: nil, x: 0.953, y: 0.686, width: 0.040, height: 0.102),
        PlanBlock("Appliances", zone: "Appliances", x: 0.411, y: 0.973, width: 0.393, height: 0.025),
        PlanBlock("Coolers", zone: "Back-wall coolers", x: 0.370, y: 0.053, width: 0.078, height: 0.217),
        PlanBlock("Home & auto", zone: "Home & auto", x: 0.410, y: 0.673, width: 0.104, height: 0.276),
        PlanBlock("Computers", zone: "Electronics & optical", x: 0.814, y: 0.695, width: 0.067, height: 0.111),
        PlanBlock("Lockers", zone: "Pharmacy lockers", x: 0.945, y: 0.499, width: 0.040, height: 0.142),
    ], entranceX: 0.910, entranceY: 1.0)

    /// The floor plan drawing for a store with these zones: a layout's plan when most of its zones are the store's.
    public static func plan(forZones zoneNames: [String]) -> PlanDrawing? {
        let names = Set(zoneNames.map(ItemName.normalized))
        guard !names.isEmpty else { return nil }
        return layouts.compactMap(\.plan).first { plan in
            let planZones = Set(plan.zones.map(ItemName.normalized))
            return planZones.intersection(names).count * 2 > max(planZones.count, names.count)
        }
    }
}
