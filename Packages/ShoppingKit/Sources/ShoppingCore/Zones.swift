import Foundation

/// Starting zone lists for a new store. Zones are the parts of the store you walk through, in walking order, not
/// grocery categories: a Costco isn't laid out by "Dairy" and "Snacks".
public enum DefaultZones {
    /// A Costco warehouse, front door to checkout.
    public static let costco = [
        "Entrance electronics",
        "Center tables",
        "Paper goods",
        "Pantry aisles",
        "Meat",
        "Back cooler wall",
        "Frozen",
        "Bakery",
        "Rotisserie corner",
    ]

    /// Any other store.
    public static let generic = [
        "Produce",
        "Bakery",
        "Pantry",
        "Dairy",
        "Meat",
        "Frozen",
        "Household",
    ]

    /// The Aurora Village Costco (Shoreline, WA), from its floor plan: in from the entrance at the front right, left
    /// along the front, round the back wall, down the middle to the checkout, then the food court and the pharmacy
    /// lockers on the way out.
    public static let costcoAuroraVillage = [
        "Electronics & optical",
        "Appliances",
        "Home & auto",
        "Adult beverages",
        "Produce",
        "Bakery",
        "Meat",
        "Rotisserie & deli",
        "Dairy & center coolers",
        "Paper goods & water",
        "Laundry, cleaning & pet",
        "Beverages, soda & Gatorade",
        "Frozen",
        "Back-wall coolers",
        "Pantry",
        "Snacks (top wall)",
        "Medicine & pharmacy",
        "Snacks, clothing & seasonal",
        "Checkout",
        "Food court",
        "Pharmacy lockers",
    ]

    /// Zone lists a store can start again from (in the Zones sheet).
    public static let layouts = [
        ZoneLayout(name: "Costco Aurora Village", detail: "From your floor plan", zones: costcoAuroraVillage),
        ZoneLayout(name: "Costco", detail: "A typical warehouse", zones: costco),
        ZoneLayout(name: "Any store", detail: "Grocery basics", zones: generic),
    ]

    /// The zones to start a store called `storeName` with: the Aurora Village floor plan for that Costco, Costco's
    /// for any other Costco, the generic list otherwise.
    public static func zones(forStoreNamed storeName: String) -> [String] {
        let name = ItemName.normalized(storeName)
        guard name.contains("costco") else { return generic }
        return name.contains("aurora") ? costcoAuroraVillage : costco
    }
}

/// A named list of zones in walking order.
public struct ZoneLayout: Sendable, Equatable, Hashable {
    public var name: String
    public var detail: String
    public var zones: [String]

    public init(name: String, detail: String, zones: [String]) {
        self.name = name
        self.detail = detail
        self.zones = zones
    }

    /// Whether `zoneNames` already are this layout (compared normalized, in order).
    public func matches(_ zoneNames: [String]) -> Bool {
        zoneNames.map(ItemName.normalized) == zones.map(ItemName.normalized)
    }
}
