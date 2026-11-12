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
    public var learning: RouteLearning
    public var wandering: Wandering

    public init(context: NSManagedObjectContext, policy: TripPolicy = TripPolicy(),
                learning: RouteLearning = RouteLearning(), wandering: Wandering = Wandering()) {
        self.context = context
        self.policy = policy
        self.learning = learning
        self.wandering = wandering
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

    /// Replaces the store's zones with `names`, in that walking order. A zone whose name (compared normalized) is in
    /// `names` stays, with its items; items in the zones that go away lose their zone, and can be guessed again.
    /// Blank and repeated names are skipped.
    public func replaceZones(of store: Store, with names: [String]) {
        var wanted: [String] = []
        var seen = Set<String>()
        for name in names.map(ItemName.cleaned) where !name.isEmpty && seen.insert(ItemName.normalized(name)).inserted {
            wanted.append(name)
        }
        let old = store.sortedZones
        var kept = Set<Zone>()
        for (index, name) in wanted.enumerated() {
            let key = ItemName.normalized(name)
            let zone = old.first { !kept.contains($0) && ItemName.normalized($0.displayName) == key } ?? {
                let zone = insert(Zone.self, alongside: store)
                zone.id = UUID()
                zone.store = store
                return zone
            }()
            zone.name = name
            zone.sortIndex = Int64(index)
            kept.insert(zone)
        }
        for zone in old where !kept.contains(zone) {
            for item in zone.items ?? [] {
                item.storeZone = nil
                item.zoneSource = nil
            }
            context.delete(zone)
        }
        context.processPendingChanges()
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
        // New things go at the bottom of your order at home.
        let place = HomeOrder.next(after: store.entries.map(\.homePlace))
        let entry = insert(ListEntry.self, alongside: store)
        entry.id = UUID()
        entry.quantity = 1
        entry.createdAt = now
        entry.homeOrder = NSNumber(value: place)
        entry.addedByID = shopper.id
        entry.addedByName = shopper.name
        entry.item = item
        return entry
    }

    /// Sets an item's zone by hand (including "no zone"). A zone set by hand is never replaced by a guess.
    public func setZone(_ zone: Zone?, for item: Item) {
        item.storeZone = zone
        item.zoneSource = ZoneSource.manual
    }

    /// Marks a guessed zone as right, as if it had been set by hand.
    public func confirmZone(of item: Item) {
        if item.zoneSource == ZoneSource.guessed { item.zoneSource = ZoneSource.manual }
    }

    // MARK: Guessing zones (issue #4)

    /// Whether the on-device model should guess the item's zone: it has none, nobody has set or guessed one (a guess
    /// is written to the shared record, so the other phone doesn't guess again), and the store has zones.
    public func needsZoneGuess(_ item: Item) -> Bool {
        !item.isDeleted && item.storeZone == nil && item.zoneSource == nil && !(item.store?.zones ?? []).isEmpty
    }

    /// The store's zones in walking order, each with a few items already in it (the ones placed by hand or bought
    /// most often first), as examples for the model.
    public func zoneExamples(in store: Store) -> [ZoneExamples] {
        store.sortedZones.map { zone in
            let items = (zone.items ?? []).filter { !$0.isDeleted && $0.zoneSource != ZoneSource.guessed }
                .sorted { ($1.positionSampleCount, $0.displayName) < ($0.positionSampleCount, $1.displayName) }
            return ZoneExamples(name: zone.displayName,
                                items: items.prefix(ZoneGuess.examplesPerZone).map(\.displayName))
        }
    }

    /// Gives the item the zone the model answered, marked as guessed, unless it got a zone meanwhile (by hand, or a
    /// guess from the other phone) or the answer isn't one of the store's zones. Returns the zone it got.
    @discardableResult
    public func applyZoneGuess(_ answer: String?, to item: Item) -> Zone? {
        guard needsZoneGuess(item), let store = item.store else { return nil }
        let zones = store.sortedZones
        guard let index = ZoneGuess.resolve(answer, zoneNames: zones.map(\.displayName)) else { return nil }
        item.storeZone = zones[index]
        item.zoneSource = ZoneSource.guessed
        return zones[index]
    }

    // MARK: Moving items by hand

    /// Writes positions from a drag on the list (`ListOrdering.positionsAfterMove`). The moved item's recent samples
    /// start again from where it was put, so trips refine the new place instead of snapping back to the old one.
    public func place(_ positions: [Item: Double], moved: Item) {
        for (item, position) in positions {
            let p = min(max(position, 0), 1)
            item.learnedPosition = NSNumber(value: p)
            if item == moved { item.recentPositions = LearnedPosition.encode([p]) }
        }
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
    /// Takes the entry off the list. The item stays remembered (Past items, Everything). Returns what Undo needs to
    /// put it back with `restore(_:)`.
    @discardableResult
    public func remove(_ entry: ListEntry) -> RemovedEntry? {
        let removed = entry.item.map {
            RemovedEntry(item: $0, name: entry.displayName, quantity: entry.quantity, note: entry.note,
                         isChecked: entry.isChecked, createdAt: entry.createdAt, homeOrder: entry.homeOrder,
                         addedByID: entry.addedByID, addedByName: entry.addedByName,
                         checkedByID: entry.checkedByID, checkedByName: entry.checkedByName)
        }
        context.delete(entry)
        context.processPendingChanges()
        return removed
    }

    /// Puts a removed entry back where it was (Undo). If the item went back on the list in the meantime, that line
    /// gets its count instead of a second line. Returns nil once the item itself is gone.
    @discardableResult
    public func restore(_ removed: RemovedEntry) -> ListEntry? {
        let item = removed.item
        guard !item.isDeleted, item.managedObjectContext === context, let store = item.store else { return nil }
        if !removed.isChecked, let open = (item.entries ?? []).first(where: { !$0.isChecked && !$0.isDeleted }) {
            open.quantity += max(removed.quantity, 1)
            return open
        }
        let entry = insert(ListEntry.self, alongside: store)
        entry.id = UUID()
        entry.quantity = max(removed.quantity, 1)
        entry.note = removed.note
        entry.isChecked = removed.isChecked
        entry.createdAt = removed.createdAt
        entry.homeOrder = removed.homeOrder
        entry.addedByID = removed.addedByID
        entry.addedByName = removed.addedByName
        entry.checkedByID = removed.checkedByID
        entry.checkedByName = removed.checkedByName
        entry.item = item
        context.processPendingChanges()
        return entry
    }

    // MARK: Remembered items

    /// Whether the item is on the list and not yet checked off.
    public func isOnList(_ item: Item) -> Bool {
        (item.entries ?? []).contains { !$0.isChecked && !$0.isDeleted }
    }

    /// Renames a remembered item. Refuses (returns false) a blank name, or one the store already remembers as another
    /// item.
    @discardableResult
    public func renameItem(_ item: Item, to name: String) -> Bool {
        let cleaned = ItemName.cleaned(name)
        guard !cleaned.isEmpty, let store = item.store else { return false }
        if let other = self.item(named: cleaned, in: store), other != item { return false }
        item.name = cleaned
        item.normalizedName = ItemName.normalized(cleaned)
        return true
    }

    /// Forgets an item: it comes off the list and out of the suggestions, and its check-offs go with it.
    public func forget(_ item: Item) {
        context.delete(item)
        context.processPendingChanges()
    }

    /// The store's most recently ended trip that checked something off (by anyone).
    public func lastTrip(at store: Store) -> Trip? {
        (store.trips ?? []).filter { $0.endedAt != nil && !$0.isDeleted && !route(of: $0).isEmpty }
            .max { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
    }

    /// The items a trip checked off, each once, in the order they were checked off.
    public func items(boughtOn trip: Trip) -> [Item] {
        var seen = Set<Item>()
        return route(of: trip).compactMap(\.item).filter { !$0.isDeleted && seen.insert($0).inserted }
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
    /// check-off again, so a mis-tap teaches nothing. Returns the new check-off when checking off.
    @discardableResult
    public func setChecked(_ entry: ListEntry, _ checked: Bool, by shopper: Shopper, source: String = "tap",
                           now: Date = Date()) -> CheckOff? {
        guard entry.isChecked != checked, let item = entry.item, let store = item.store else { return nil }
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
            return checkOff
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
            return nil
        }
    }

    // MARK: The floor plan (issue #5)

    /// Where the item is on the floor plan: the median of its most recent mapped check-offs.
    public func spot(of item: Item) -> FloorPoint? {
        FloorPlan.median(recentPoints(of: item))
    }

    /// The item's spot once it has settled enough to correct a trip's drift (see `FloorPlan.landmark`).
    public func landmark(of item: Item) -> FloorPoint? {
        FloorPlan.landmark(recentPoints(of: item))
    }

    /// Where the store's checkout is: the median of where recent mapped trips ended.
    public func checkoutSpot(in store: Store) -> FloorPoint? {
        let ends = (store.trips ?? []).filter { $0.endedAt != nil && !$0.isDeleted }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
            .compactMap { $0.floorPath.last }
            .prefix(FloorPlan.recentPoints)
        return FloorPlan.median(Array(ends))
    }

    /// The most recently ended mapped trip at the store.
    public func lastMappedTrip(at store: Store) -> Trip? {
        (store.trips ?? []).filter { $0.endedAt != nil && $0.path != nil && !$0.isDeleted }
            .max { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
    }

    /// Puts a mapped point on a check-off.
    public func setPoint(_ point: FloorPoint?, of checkOff: CheckOff) {
        checkOff.x = point.map { NSNumber(value: $0.x) }
        checkOff.y = point.map { NSNumber(value: $0.y) }
    }

    /// Saves a mapped trip's walk (drift corrected) and its check-offs' corrected points. A check-off that was
    /// unchecked again is skipped.
    public func recordPath(_ path: [FloorPoint], points: [CheckOff: FloorPoint], of trip: Trip) {
        trip.path = FloorPlan.encode(FloorPlan.thinned(path))
        for (checkOff, point) in points where !checkOff.isDeleted && checkOff.managedObjectContext != nil {
            setPoint(point, of: checkOff)
        }
    }

    private func recentPoints(of item: Item) -> [FloorPoint] {
        (item.checkOffs ?? []).filter { !$0.isDeleted }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            .compactMap(\.floorPoint)
            .prefix(FloorPlan.recentPoints)
            .map { $0 }
    }

    /// Learns the store's order from the trip's route: each item checked off on it moves toward where in the trip it
    /// was grabbed. A trip teaches once (ending a trip does this); a trip with fewer than two check-offs that count
    /// teaches nothing. Returns how many items learned something.
    @discardableResult
    public func learn(from trip: Trip, now: Date = Date()) -> Int {
        guard trip.learnedAt == nil else { return 0 }
        trip.learnedAt = trip.endedAt ?? now
        let stops = route(of: trip).compactMap { checkOff -> RouteStop<Item>? in
            guard let item = checkOff.item, !item.isDeleted, let time = checkOff.timestamp else { return nil }
            return RouteStop(item: item, time: time)
        }
        let byRank = learning.rankPositions(stops)
        let byTime = learning.timePositions(stops)
        for (item, sample) in byRank {
            let next = learning.updated(item.learned, with: sample)
            item.learnedPosition = next.position.map { NSNumber(value: $0) }
            item.positionSampleCount = Int64(next.sampleCount)
            item.recentPositions = LearnedPosition.encode(next.recent)
            // Still learning while it wanders, so it goes back into the sort once it settles.
            let wanders = wandering.isWandering(next.recent, wasWandering: item.isWandering)
            if item.isWandering != wanders { item.isWandering = wanders }
            if let timeSample = byTime[item] {
                item.learnedTimePosition = NSNumber(value: learning.smoothed(item.learnedTimePosition?.doubleValue,
                                                                             with: timeSample))
            }
        }
        return byRank.count
    }

    /// Sets "This moves around" (`.wanders`) or "This has a fixed spot" (`.fixed`) on `item`, or nil to go by what
    /// the trips say. It's on the item, so it's shared with the list.
    public func setWanderOverride(_ choice: WanderOverride?, for item: Item) {
        if item.wanderOverride != choice?.rawValue { item.wanderOverride = choice?.rawValue }
    }

    /// Where a wandering item has been seen, for its row (see `Wandering.note`).
    public func wanderNote(for item: Item) -> String? {
        wandering.note(item.learned.recent)
    }

    /// The average learned position of each of the store's zones that has any (for items not learned yet). Items
    /// that wander are left out: their positions say nothing about their zone's place in the walk.
    public func zonePositions(in store: Store) -> [Zone: Double] {
        let zones = store.sortedZones
        let averages = ListOrdering.zoneAverages((store.items ?? []).filter { !$0.isDeleted && !$0.wanders }.map { item in
            (zone: item.storeZone.flatMap { zones.firstIndex(of: $0) }, position: item.learnedPosition?.doubleValue)
        })
        var result: [Zone: Double] = [:]
        for (index, average) in averages where zones.indices.contains(index) { result[zones[index]] = average }
        return result
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
        learn(from: trip, now: date)
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
/// A list entry that `ListService.remove(_:)` took off, kept so Undo can put it back (`ListService.restore(_:)`).
public struct RemovedEntry {
    /// The item's name, for "Removed …".
    public let name: String
    let item: Item
    let quantity: Int64
    let note: String?
    let isChecked: Bool
    let createdAt: Date?
    let homeOrder: NSNumber?
    let addedByID: String?
    let addedByName: String?
    let checkedByID: String?
    let checkedByName: String?

    init(item: Item, name: String, quantity: Int64, note: String?, isChecked: Bool, createdAt: Date?,
         homeOrder: NSNumber?, addedByID: String?, addedByName: String?, checkedByID: String?,
         checkedByName: String?) {
        self.item = item
        self.name = name
        self.quantity = quantity
        self.note = note
        self.isChecked = isChecked
        self.createdAt = createdAt
        self.homeOrder = homeOrder
        self.addedByID = addedByID
        self.addedByName = addedByName
        self.checkedByID = checkedByID
        self.checkedByName = checkedByName
    }
}
#endif
