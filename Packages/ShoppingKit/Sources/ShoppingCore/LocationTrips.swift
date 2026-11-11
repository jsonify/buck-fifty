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
    case endTrip
    case nothing
}

/// Starting and ending trips by location. Arriving starts a trip only when there's something on the list (driving past
/// on the way somewhere else shouldn't), and never a second one. Leaving ends the trip that's going, so a trip you
/// forgot to end doesn't run on until it goes quiet.
public enum LocationTrips {
    public static func action(for crossing: StoreCrossing, hasOpenTrip: Bool, itemsLeft: Int) -> LocationTripAction {
        switch crossing {
        case .arrived: return !hasOpenTrip && itemsLeft > 0 ? .startTrip : .nothing
        case .left: return hasOpenTrip ? .endTrip : .nothing
        }
    }
}
