#if canImport(CoreData)
import CoreData
import Foundation
import ShoppingCore

/// Everything the app does to a list, on one context. It doesn't save; call `save()` when a change is done.
///
/// New objects are put in the same persistent store as the store they belong to. That matters once a list is
/// shared: a shared store lives in the shared CloudKit database, and an item added to it has to go there too, or the
/// other person never sees it.
public struct ListService {
    public let context: NSManagedObjectContext
    public var policy: TripPolicy

    public init(context: NSManagedObjectContext, policy: TripPolicy = TripPolicy()) {
        self.context = context
        self.policy = policy
    }

    // MARK: Stores and zones

    /// A new store with `zoneNames` in that walking order (by default the zones for its name: Costco's for a Costco).
    @discardableResult
    public func createStore(named name: String, zoneNames: [String]? = nil, now: Date = Date()) -> Store {
        let store = insert(Store.self, alongside: nil)
        store.id = UUID()
        store.name = ItemName.cleaned(name)
        store.createdAt = now
        for (index, zoneName) in (zoneNames ?? DefaultZones.zones(forStoreNamed: name)).enumerated() {
            let zone = insert(Zone.self, alongside: store)
            zone.id = UUID()
            zone.name = zoneName
            zone.sortIndex = Int64(index)
            zone.store = store
        }
        return store
    }

    /// A zone added at the end of the walk.
    @discardableResult
    public func addZone(named name: String, to store: Store) -> Zone {
        let zone = insert(Zone.self, alongside: store)
        zone.id = UUID()
        zone.name = ItemName.cleaned(name)
        zone.sortIndex = Int64((store.sortedZones.last?.sortIndex ?? -1) + 1)
        zone.store = store
        return zone
    }

    /// Moves the zone at `from` to `to` in the walking order and renumbers them all.
    public func moveZone(in store: Store, from: Int, to: Int) {
        var zones = store.sortedZones
        guard zones.indices.contains(from), zones.indices.contains(to), from != to else { return }
        zones.insert(zones.remove(at: from), at: to)
        for (index, zone) in zones.enumerated() where zone.sortIndex != Int64(index) {
            zone.sortIndex = Int64(index)
        }
    }

    /// Deletes a zone; its items keep their place on the list but lose their zone.
    public func deleteZone(_ zone: Zone) {
        let store = zone.store
        context.delete(zone)
        context.processPendingChanges()
        if let store {
            for (index, z) in store.sortedZones.filter({ $0 != zone }).enumerated() { z.sortIndex = Int64(index) }
        }
    }

    // MARK: Items and the list

    /// The item this store remembers under `name` (compared normalized), if any.
    public func item(named name: String, in store: Store) -> Item? {
        let key = ItemName.normalized(name)
        return (store.items ?? []).first { $0.normalizedName == key }
    }

    /// Remembered items matching `query`, best first, for autocomplete.
    public func suggestions(for query: String, in store: Store, limit: Int = 5) -> [Item] {
        ItemSuggester.suggestions(for: query, in: Array(store.items ?? []), limit: limit) { $0.displayName }
    }

    /// Puts `name` on the list. A name the store remembers reuses that item (and its zone); one already on the list
    /// and not yet checked off gets one more instead of a second line. Returns nil for a blank name.
    @discardableResult
    public func addToList(_ name: String, store: Store, by shopper: Shopper, now: Date = Date()) -> ListEntry? {
        let cleaned = ItemName.cleaned(name)
        guard !cleaned.isEmpty else { return nil }
        let item = self.item(named: cleaned, in: store) ?? {
            let item = insert(Item.self, alongside: store)
            item.id = UUID()
            item.name = cleaned
            item.normalizedName = ItemName.normalized(cleaned)
            item.createdAt = now
            item.store = store
            return item
        }()
        if let open = (item.entries ?? []).first(where: { !$0.isChecked && !$0.isDeleted }) {
            open.quantity += 1
            return open
        }
        let entry = insert(ListEntry.self, alongside: store)
        entry.id = UUID()
        entry.quantity = 1
        entry.createdAt = now
        entry.addedByID = shopper.id
        entry.addedByName = shopper.name
        entry.item = item
        return entry
    }

    /// Sets an item's zone by hand.
    public func setZone(_ zone: Zone?, for item: Item) {
        item.storeZone = zone
        item.zoneSource = zone == nil ? nil : "manual"
    }

    /// Renames an item. If the store already remembers the new name as another item, this entry moves to that item
    /// instead. Returns the item the entry now belongs to.
    @discardableResult
    public func rename(_ entry: ListEntry, to name: String) -> Item? {
        let cleaned = ItemName.cleaned(name)
        guard !cleaned.isEmpty, let item = entry.item, let store = item.store else { return entry.item }
        if let other = self.item(named: cleaned, in: store), other != item {
            entry.item = other
            return other
        }
        item.name = cleaned
        item.normalizedName = ItemName.normalized(cleaned)
        return item
    }

    /// Takes an entry off the list. The item is still remembered.
    public func remove(_ entry: ListEntry) {
        context.delete(entry)
        context.processPendingChanges()
    }

    // MARK: Trips and check-offs

    /// The shopper's trip at this store that is still going, if any. Trips that have gone quiet are ended on the way.
    public func currentTrip(at store: Store, for shopper: Shopper, now: Date = Date()) -> Trip? {
        endLapsedTrips(at: store, now: now)
        return openTrips(at: store).first { $0.shopperID == shopper.id }
    }

    /// The shopper's trip that is still going, without changing anything (safe to call while drawing a view).
    public func activeTrip(among trips: [Trip], for shopper: Shopper, now: Date = Date()) -> Trip? {
        trips.filter { trip in
            trip.endedAt == nil && trip.shopperID == shopper.id
                && !policy.hasLapsed(lastActivity: trip.lastActivityAt ?? trip.startedAt ?? now, now: now)
        }
        .max { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    /// Starts a trip for the shopper (or returns the one already going).
    @discardableResult
    public func startTrip(at store: Store, for shopper: Shopper, now: Date = Date()) -> Trip {
        if let trip = currentTrip(at: store, for: shopper, now: now) { return trip }
        let trip = insert(Trip.self, alongside: store)
        trip.id = UUID()
        trip.shopperID = shopper.id
        trip.shopperName = shopper.name
        trip.startedAt = now
        trip.lastActivityAt = now
        trip.store = store
        return trip
    }

    /// Ends the shopper's trip: what they checked off is bought, so it comes off the list (the items stay remembered).
    public func finishTrip(at store: Store, for shopper: Shopper, now: Date = Date()) {
        guard let trip = currentTrip(at: store, for: shopper, now: now) else { return }
        end(trip, at: now)
    }

    /// Checks an entry off or back on. Checking off during no trip starts one; every check-off is recorded with its
    /// time on the trip, which is the route later issues learn from. Unchecking during the trip removes that
    /// check-off again, so a mis-tap teaches nothing.
    public func setChecked(_ entry: ListEntry, _ checked: Bool, by shopper: Shopper, source: String = "tap",
                           now: Date = Date()) {
        guard entry.isChecked != checked, let item = entry.item, let store = item.store else { return }
        if checked {
            let trip = startTrip(at: store, for: shopper, now: now)
            let checkOff = insert(CheckOff.self, alongside: store)
            checkOff.id = UUID()
            checkOff.timestamp = now
            checkOff.source = source
            checkOff.trip = trip
            checkOff.item = item
            trip.lastActivityAt = now
            entry.isChecked = true
            entry.checkedByID = shopper.id
            entry.checkedByName = shopper.name
        } else {
            if let trip = currentTrip(at: store, for: shopper, now: now),
               let last = (trip.checkOffs ?? []).filter({ $0.item == item })
                   .max(by: { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }) {
                context.delete(last)
                context.processPendingChanges()
                trip.lastActivityAt = now
            }
            entry.isChecked = false
            entry.checkedByID = nil
            entry.checkedByName = nil
        }
    }

    /// The trip's check-offs in the order they happened.
    public func route(of trip: Trip) -> [CheckOff] {
        (trip.checkOffs ?? []).filter { !$0.isDeleted }.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    }

    // MARK: Saving

    public func save() throws {
        if context.hasChanges { try context.save() }
    }

    // MARK: Private

    private func openTrips(at store: Store) -> [Trip] {
        (store.trips ?? []).filter { $0.endedAt == nil }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    private func endLapsedTrips(at store: Store, now: Date) {
        for trip in openTrips(at: store) {
            let last = trip.lastActivityAt ?? trip.startedAt ?? now
            if policy.hasLapsed(lastActivity: last, now: now) { end(trip, at: last) }
        }
    }

    private func end(_ trip: Trip, at date: Date) {
        trip.endedAt = date
        guard let store = trip.store, let shopperID = trip.shopperID else { return }
        for entry in store.entries where entry.isChecked && entry.checkedByID == shopperID {
            context.delete(entry)
        }
        context.processPendingChanges()
    }

    /// A new object in the same persistent store as `anchor`. An anchor that hasn't been saved yet has no store; Core
    /// Data then puts both in the first store, which is the private one, where a new store belongs.
    private func insert<T: NSManagedObject>(_ type: T.Type, alongside anchor: NSManagedObject?) -> T {
        // By entity name (the class's Swift name), not T(context:): the model is built in code, and looking an
        // entity up by class can fail to find it.
        guard let entity = NSEntityDescription.entity(forEntityName: String(describing: type), in: context) else {
            preconditionFailure("No entity for \(type) in the model")
        }
        let object = T(entity: entity, insertInto: context)
        if let store = anchor?.objectID.persistentStore {
            context.assign(object, to: store)
        }
        return object
    }
}
#endif
