import Foundation

/// Where a store is, kept on this phone for starting and ending trips by location: a circle around the store that the
/// phone watches. The centre is where you stood when you pinned it; the radius takes in the car park, so a trip ends
/// once you drive away, not at the door.
public struct StorePin: Sendable, Equatable, Codable {
    public var latitude: Double
    public var longitude: Double
    /// Metres.
    public var radius: Double

    /// The radius a new pin gets: a big box store and most of its car park.
    public static let defaultRadius = 200.0
    /// The radii to choose from: a small store, a big one, and a big one in a wide car park.
    public static let radii: [Double] = [100, 200, 400]

    public init(latitude: Double, longitude: Double, radius: Double = StorePin.defaultRadius) {
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }

    /// Pins by store id, as kept in the app's settings (JSON); empty for nothing or anything unreadable.
    public static func decode(_ data: Data?) -> [String: StorePin] {
        guard let data, let pins = try? JSONDecoder().decode([String: StorePin].self, from: data) else { return [:] }
        return pins
    }

    public static func encode(_ pins: [String: StorePin]) -> Data? {
        try? JSONEncoder().encode(pins)
    }
}

/// What the phone noticed about a pinned store.
public enum StoreCrossing: Sendable, Equatable {
    /// It came inside the store's circle.
    case arrived
    /// It went back out.
    case left
}

/// What a crossing does to your trip.
public enum LocationTripAction: Sendable, Equatable {
    case startTrip
    /// The phone went out of the circle during a trip: the trip ends if it isn't back inside within
    /// `LocationTrips.leaveGrace` (`PendingLeaves`).
    case leaving
    case nothing
}

/// Starting and ending trips by location. Arriving starts a trip only when there's something on the list (driving past
/// on the way somewhere else shouldn't), and never a second one. Leaving ends the trip that's going, so a trip you
/// forgot to end doesn't run on until it goes quiet; but only once you've been out for a while, because inside a big
/// store the phone's location wanders, and a moment "outside" mustn't end the trip you're in the middle of.
public enum LocationTrips {
    /// How long the phone has to stay out of the circle before the trip ends.
    public static let leaveGrace: TimeInterval = 10 * 60

    public static func action(for crossing: StoreCrossing, hasOpenTrip: Bool, itemsLeft: Int) -> LocationTripAction {
        switch crossing {
        case .arrived: return !hasOpenTrip && itemsLeft > 0 ? .startTrip : .nothing
        case .left: return hasOpenTrip ? .leaving : .nothing
        }
    }
}

/// The stores the phone has gone out of during a trip and not come back into, with when it went out. Kept on this
/// phone, like the pins. A trip ends once its store's leave is due; coming back in first cancels it.
public struct PendingLeaves: Sendable, Equatable, Codable {
    public private(set) var leftAt: [String: Date]

    public init(_ leftAt: [String: Date] = [:]) {
        self.leftAt = leftAt
    }

    /// The phone went out of the store's circle at `date`. A second report keeps the first time.
    public mutating func left(_ storeID: String, at date: Date) {
        leftAt[storeID] = min(leftAt[storeID] ?? date, date)
    }

    /// The phone is back inside (or the trip ended some other way): nothing to end.
    public mutating func cancel(_ storeID: String) {
        leftAt[storeID] = nil
    }

    /// The stores whose trips have ended by `now`, with when the phone went out (the trip's end).
    public func due(now: Date, grace: TimeInterval = LocationTrips.leaveGrace) -> [String: Date] {
        leftAt.filter { now.timeIntervalSince($0.value) >= grace }
    }

    /// As kept in the app's settings (JSON); empty for nothing or anything unreadable.
    public static func decode(_ data: Data?) -> PendingLeaves {
        guard let data, let leaves = try? JSONDecoder().decode(PendingLeaves.self, from: data) else { return .init() }
        return leaves
    }

    public static func encode(_ leaves: PendingLeaves) -> Data? {
        try? JSONEncoder().encode(leaves)
    }
}
