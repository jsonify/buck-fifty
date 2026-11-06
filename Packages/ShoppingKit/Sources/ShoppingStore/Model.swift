#if canImport(CoreData)
import CoreData
import Foundation
import ShoppingCore

// The data model, built in code so there is no .xcdatamodeld to edit by hand. It follows NSPersistentCloudKitContainer's
// rules, so it can be mirrored to iCloud and shared: every attribute is optional or has a default, every relationship
// is optional and has an inverse, nothing is ordered and there are no unique constraints.
//
// Store ─< Zone          a store's zones, in walking order (sortIndex)
//   │  ─< Item >─ Zone   everything the store remembers; an item may have a zone (storeZone)
//   │        └─< ListEntry   the item on the current list
//   │        └─< CheckOff
//   └─< Trip ─< CheckOff     one shopper's trip, and what they checked off, when
//
// Sharing a Store (see Persistence) shares everything that hangs off it.

@objc(BFStore)
public final class Store: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var zones: Set<Zone>?
    @NSManaged public var items: Set<Item>?
    @NSManaged public var trips: Set<Trip>?
}

@objc(BFZone)
public final class Zone: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var sortIndex: Int64
    @NSManaged public var store: Store?
    @NSManaged public var items: Set<Item>?
}

@objc(BFItem)
public final class Item: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    /// `ItemName.normalized(name)`: how the item is found again when it's typed.
    @NSManaged public var normalizedName: String?
    /// Where in a trip the item is grabbed, 0 (entrance) to 1 (checkout); learned from check-offs (issue #3).
    @NSManaged public var learnedPosition: NSNumber?
    /// How many trips have taught `learnedPosition`.
    @NSManaged public var positionSampleCount: Int64
    /// The latest positions trips found the item at, oldest first, as text ("0.250,0.800"; `LearnedPosition`).
    @NSManaged public var recentPositions: String?
    /// The same position learned by time on the trip instead of rank, kept to compare the two on real trips.
    @NSManaged public var learnedTimePosition: NSNumber?
    /// The warehouse item number from a shelf tag (issue #6).
    @NSManaged public var itemNumber: String?
    /// Never settles into one position (issue #8).
    @NSManaged public var isWandering: Bool
    /// How the zone was set: "manual" (by hand, also for "no zone"), or "guessed" by the on-device model (issue #4);
    /// nil when nobody has set or guessed one. See `ZoneSource`.
    @NSManaged public var zoneSource: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var store: Store?
    /// The item's zone. Not called `zone`: NSObject already has a `-zone` method (the old NSZone allocator), and a
    /// Core Data accessor by that name crashes the runtime.
    @NSManaged public var storeZone: Zone?
    @NSManaged public var entries: Set<ListEntry>?
    @NSManaged public var checkOffs: Set<CheckOff>?
}

@objc(BFListEntry)
public final class ListEntry: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var quantity: Int64
    @NSManaged public var note: String?
    @NSManaged public var isChecked: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var addedByID: String?
    @NSManaged public var addedByName: String?
    @NSManaged public var checkedByID: String?
    @NSManaged public var checkedByName: String?
    @NSManaged public var item: Item?
}

@objc(BFTrip)
public final class Trip: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var shopperID: String?
    @NSManaged public var shopperName: String?
    @NSManaged public var startedAt: Date?
    @NSManaged public var endedAt: Date?
    @NSManaged public var lastActivityAt: Date?
    /// When the store's order was learned from this trip, so a trip only teaches it once.
    @NSManaged public var learnedAt: Date?
    @NSManaged public var store: Store?
    @NSManaged public var checkOffs: Set<CheckOff>?
}

@objc(BFCheckOff)
public final class CheckOff: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    /// "tap", "scan" (issue #6) or "watch" (issue #7).
    @NSManaged public var source: String?
    /// Dead-reckoning position in metres from the entrance (issue #5).
    @NSManaged public var x: NSNumber?
    @NSManaged public var y: NSNumber?
    @NSManaged public var trip: Trip?
    @NSManaged public var item: Item?
}

/// The values of `Item.zoneSource`.
public enum ZoneSource {
    public static let manual = "manual"
    public static let guessed = "guessed"
}

public enum ShoppingModel {
    /// The one model instance. Core Data wants a single NSManagedObjectModel per process for these classes, so every
    /// container (app, tests, previews) uses this.
    public static let model: NSManagedObjectModel = makeModel()

    private static func makeModel() -> NSManagedObjectModel {
        func entity<T: NSManagedObject>(_ type: T.Type, _ name: String) -> NSEntityDescription {
            let e = NSEntityDescription()
            e.name = name
            e.managedObjectClassName = NSStringFromClass(type)
            return e
        }
        func attribute(_ name: String, _ type: NSAttributeType, default value: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = true
            a.defaultValue = value
            return a
        }
        func relate(_ a: NSEntityDescription, _ aName: String, toMany aMany: Bool, deleteRule aRule: NSDeleteRule,
                    _ b: NSEntityDescription, _ bName: String, toMany bMany: Bool, deleteRule bRule: NSDeleteRule) {
            let ab = NSRelationshipDescription(), ba = NSRelationshipDescription()
            ab.name = aName
            ab.destinationEntity = b
            ab.minCount = 0
            ab.maxCount = aMany ? 0 : 1
            ab.isOptional = true
            ab.deleteRule = aRule
            ba.name = bName
            ba.destinationEntity = a
            ba.minCount = 0
            ba.maxCount = bMany ? 0 : 1
            ba.isOptional = true
            ba.deleteRule = bRule
            ab.inverseRelationship = ba
            ba.inverseRelationship = ab
            a.properties.append(ab)
            b.properties.append(ba)
        }

        let store = entity(Store.self, "Store")
        store.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType, default: ""),
            attribute("createdAt", .dateAttributeType),
        ]
        let zone = entity(Zone.self, "Zone")
        zone.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType, default: ""),
            attribute("sortIndex", .integer64AttributeType, default: 0),
        ]
        let item = entity(Item.self, "Item")
        item.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType, default: ""),
            attribute("normalizedName", .stringAttributeType, default: ""),
            attribute("learnedPosition", .doubleAttributeType),
            attribute("positionSampleCount", .integer64AttributeType, default: 0),
            attribute("recentPositions", .stringAttributeType),
            attribute("learnedTimePosition", .doubleAttributeType),
            attribute("itemNumber", .stringAttributeType),
            attribute("isWandering", .booleanAttributeType, default: false),
            attribute("zoneSource", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
        ]
        let entry = entity(ListEntry.self, "ListEntry")
        entry.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("quantity", .integer64AttributeType, default: 1),
            attribute("note", .stringAttributeType),
            attribute("isChecked", .booleanAttributeType, default: false),
            attribute("createdAt", .dateAttributeType),
            attribute("addedByID", .stringAttributeType),
            attribute("addedByName", .stringAttributeType),
            attribute("checkedByID", .stringAttributeType),
            attribute("checkedByName", .stringAttributeType),
        ]
        let trip = entity(Trip.self, "Trip")
        trip.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("shopperID", .stringAttributeType),
            attribute("shopperName", .stringAttributeType),
            attribute("startedAt", .dateAttributeType),
            attribute("endedAt", .dateAttributeType),
            attribute("lastActivityAt", .dateAttributeType),
            attribute("learnedAt", .dateAttributeType),
        ]
        let checkOff = entity(CheckOff.self, "CheckOff")
        checkOff.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("timestamp", .dateAttributeType),
            attribute("source", .stringAttributeType, default: "tap"),
            attribute("x", .doubleAttributeType),
            attribute("y", .doubleAttributeType),
        ]

        relate(store, "zones", toMany: true, deleteRule: .cascadeDeleteRule,
               zone, "store", toMany: false, deleteRule: .nullifyDeleteRule)
        relate(store, "items", toMany: true, deleteRule: .cascadeDeleteRule,
               item, "store", toMany: false, deleteRule: .nullifyDeleteRule)
        relate(store, "trips", toMany: true, deleteRule: .cascadeDeleteRule,
               trip, "store", toMany: false, deleteRule: .nullifyDeleteRule)
        relate(zone, "items", toMany: true, deleteRule: .nullifyDeleteRule,
               item, "storeZone", toMany: false, deleteRule: .nullifyDeleteRule)
        relate(item, "entries", toMany: true, deleteRule: .cascadeDeleteRule,
               entry, "item", toMany: false, deleteRule: .nullifyDeleteRule)
        relate(item, "checkOffs", toMany: true, deleteRule: .cascadeDeleteRule,
               checkOff, "item", toMany: false, deleteRule: .nullifyDeleteRule)
        relate(trip, "checkOffs", toMany: true, deleteRule: .cascadeDeleteRule,
               checkOff, "trip", toMany: false, deleteRule: .nullifyDeleteRule)

        let model = NSManagedObjectModel()
        model.entities = [store, zone, item, entry, trip, checkOff]
        return model
    }
}

// Conveniences the views use.
extension Store {
    public var displayName: String { name ?? "" }
    /// The zones in walking order.
    public var sortedZones: [Zone] {
        (zones ?? []).sorted { ($0.sortIndex, $0.name ?? "") < ($1.sortIndex, $1.name ?? "") }
    }
    /// Every entry on the store's list.
    public var entries: [ListEntry] {
        (items ?? []).filter { !$0.isDeleted }.flatMap { ($0.entries ?? []).filter { !$0.isDeleted } }
    }
    public var remainingCount: Int { entries.filter { !$0.isChecked }.count }
}

extension Zone {
    public var displayName: String { name ?? "" }
}

extension Item {
    public var displayName: String { name ?? "" }
    /// Whether the item's zone is the on-device model's guess, not yet confirmed.
    public var isZoneGuessed: Bool { storeZone != nil && zoneSource == ZoneSource.guessed }
    /// What the store has learned about where the item is.
    public var learned: LearnedPosition {
        LearnedPosition(position: learnedPosition?.doubleValue, sampleCount: Int(positionSampleCount),
                        recent: LearnedPosition.decode(recentPositions))
    }
}

extension ListEntry {
    public var displayName: String { item?.displayName ?? "" }
}
#endif
