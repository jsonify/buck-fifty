import Foundation

/// When a trip starts and ends. A trip belongs to one shopper at one store: two people shopping the same list at
/// the same time make two trips, so their check-off orders stay separate routes.
public struct TripPolicy: Sendable, Equatable {
    /// A trip with no check-offs for this long has ended (at its last activity).
    public var quietPeriod: TimeInterval

    public init(quietPeriod: TimeInterval = 45 * 60) {
        self.quietPeriod = quietPeriod
    }

    /// Whether an open trip last active at `lastActivity` has ended by `now`.
    public func hasLapsed(lastActivity: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastActivity) >= quietPeriod
    }
}

/// The person using this phone, as the shared list sees them.
public struct Shopper: Sendable, Equatable, Hashable {
    /// Stable for this person (kept in the app's settings); trips and check-offs are tagged with it.
    public var id: String
    /// What the other person sees ("Jason").
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// Up to two letters for a name: the first letter of the first two words ("Mary Ann" → "MA", "jason" → "J"),
    /// or "?" for a blank name.
    public static func initials(of name: String) -> String {
        let letters = ItemName.cleaned(name).split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    public var initials: String { Shopper.initials(of: name) }
}
