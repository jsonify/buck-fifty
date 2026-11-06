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

    /// The zones to start a store called `storeName` with: Costco's for a Costco, the generic list otherwise.
    public static func zones(forStoreNamed storeName: String) -> [String] {
        ItemName.normalized(storeName).contains("costco") ? costco : generic
    }
}
