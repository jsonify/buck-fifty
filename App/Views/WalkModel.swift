import CoreData
import Observation
import SwiftUI
import ShoppingCore
import ShoppingStore

/// A row of the list, with its zone's place in the walk and where trips found it, for `ListOrdering` and `Walk`.
struct ListRow: ListSortable {
    let entry: ListEntry
    let zoneIndex: Int?
    var learnedPosition: Double? { entry.item?.learnedPosition?.doubleValue }
    var sortName: String { entry.displayName }
    var isChecked: Bool { entry.isChecked }
    var isWandering: Bool { entry.item?.wanders == true }
}

/// A store's list as a walk, worked out once a draw for the List, the Map and Home, so all three show the same stops
/// and walk numbers.
struct WalkModel {
    let rows: [ListRow]
    let zoneNames: [String]
    let zonePositions: [Int: Double]
    let stops: [Walk.Stop<ListRow>]
    let next: (entry: ListRow, number: Int)?

    /// Each zone is one stop, in the order the walk first reaches it, so a zone never comes round twice.
    init(entries: [ListEntry], zones: [Zone], items: [Item]) {
        let rows = entries.map { entry in
            ListRow(entry: entry, zoneIndex: entry.item?.storeZone.flatMap { zones.firstIndex(of: $0) })
        }
        let zonePositions = ListOrdering.zoneAverages(items.filter { !$0.wanders }.map { item in
            (zone: item.storeZone.flatMap { zones.firstIndex(of: $0) }, position: item.learnedPosition?.doubleValue)
        })
        let zoneNames = zones.map(\.displayName)
        self.rows = rows
        self.zoneNames = zoneNames
        self.zonePositions = zonePositions
        stops = Walk.stops(rows, zoneNames: zoneNames, zonePositions: zonePositions, oneSectionPerZone: true)
        next = Walk.next(in: stops)
    }

    /// How many things are still to get.
    var left: Int { rows.filter { !$0.isChecked }.count }

    /// The walk's stops (not Look for it).
    var walkStops: [Walk.Stop<ListRow>] { stops.filter(\.isInWalk) }

    /// The stop the next item is at.
    var nextStop: Walk.Stop<ListRow>? { stops.first { $0.state == .next } }

    /// The LCD's strip in the store: a cell per stop, full once done, half for the next one. A long walk shares out
    /// its stops over at most `maxCells` cells, so the strip stays readable: a cell is full once all its stops are done.
    var strip: [StripCell] {
        let states = walkStops.map(\.state)
        let maxCells = 14
        guard states.count > maxCells else { return states.map(Self.cell) }
        return (0..<maxCells).map { cell in
            let start = cell * states.count / maxCells, end = (cell + 1) * states.count / maxCells
            let part = states[start..<end]
            if part.contains(.next) { return Self.cell(.next) }
            return Self.cell(part.allSatisfy { $0 == .done } ? .done : .ahead)
        }
    }

    private static func cell(_ state: Walk.StopState) -> StripCell {
        switch state {
        case .done: return StripCell(fill: .full)
        case .next: return StripCell(fill: .half, marked: true)
        case .ahead: return StripCell(fill: .empty)
        }
    }

    /// The walk number of each entry, by its object id.
    var numbers: [NSManagedObjectID: Int] {
        var result: [NSManagedObjectID: Int] = [:]
        for stop in stops {
            for (row, number) in zip(stop.entries, stop.numbers) {
                if let number { result[row.entry.objectID] = number }
            }
        }
        return result
    }

    /// The unchecked rows in the walk in list order, for dragging one onto another (Look for it isn't in the walk).
    var unchecked: [ListRow] {
        ListOrdering.sorted(rows, zoneCount: zoneNames.count, zonePositions: zonePositions)
            .filter { !$0.isChecked && !$0.isWandering }
    }

    /// The mark on a stop's rail node. Zones get none (the only numbers on the list are the walk numbers on the
    /// right); Look for it is a question mark and No zone yet a dash.
    static func railLabel(_ stop: Walk.Stop<ListRow>) -> String? {
        switch stop.kind {
        case .zone: return nil
        case .unzoned: return "–"
        case .lookForIt: return "?"
        }
    }
}

/// Starting and ending trips and checking things off, the same from every tab: Start trip maps the walk when Map the
/// store is on, and Done ends it at the checkout.
@MainActor
struct TripActions {
    let store: Store
    let context: NSManagedObjectContext
    let profile: Profile

    private var service: ListService { ListService(context: context) }
    private var mapper: StoreMapper { StoreMapper.shared }

    /// Starts a trip at the door: the origin of the map. With trips by location on, the first trip at a store pins
    /// it there. `atDoor` is false for a trip started by walking into the store's circle, which isn't mapped.
    func start(atDoor: Bool = true) {
        let started = service.startTrip(at: store, for: profile.shopper)
        if atDoor, profile.mapsStore, StoreMapper.isAvailable, !Launch.isDemo {
            mapper.start(started, gridHeading: store.gridHeading?.doubleValue)
        }
        if atDoor, !Launch.isDemo { StoreFence.shared.pinIfNeeded(store) }
        save()
    }

    /// Ends your trip; says whether anything was bought (then Everything opens for the review).
    func finish(_ trip: Trip?) -> Bool {
        let bought = trip.map { service.route(of: $0).count } ?? 0
        if let trip, mapper.isRecording(trip) { finishMapping(trip, atCheckout: true) }
        service.finishTrip(at: store, for: profile.shopper)
        save()
        return bought > 0
    }

    /// Checks an entry off or back on; a check-off on a mapped trip becomes a point on the map.
    func toggle(_ entry: ListEntry) {
        let checkOff = service.setChecked(entry, !entry.isChecked, by: profile.shopper)
        if let checkOff, let item = entry.item, mapper.isRecording(checkOff.trip) {
            service.setPoint(mapper.mark(checkOff, landmark: service.landmark(of: item)), of: checkOff)
        }
        save()
    }

    /// Ends trips that went quiet. A mapped trip that went quiet ended away from the checkout: keep its walk,
    /// uncorrected at the end.
    func endLapsedTrips() {
        _ = service.currentTrip(at: store, for: profile.shopper)
        if let mapped = mapper.trip, mapped.endedAt != nil, mapped.store == store {
            finishMapping(mapped, atCheckout: false)
        }
        save()
    }

    /// Saves the mapped walk of `trip`. At the checkout (Done), the walk's end is pinned to the store's checkout.
    private func finishMapping(_ trip: Trip, atCheckout: Bool) {
        let result = mapper.finish(checkout: atCheckout ? service.checkoutSpot(in: store) : nil)
        service.recordPath(result.path, points: result.points, of: trip)
        if store.gridHeading == nil, let grid = result.gridHeading { store.gridHeading = NSNumber(value: grid) }
    }

    func save() {
        do {
            try service.save()
        } catch {
            context.rollback()
            print("Buck Fifty: save failed: \(error)")
        }
    }
}

/// Where the app is: the tab, the store every tab is about, and the store chooser.
@MainActor
@Observable
final class Navigator {
    var tab: AppTab = .home
    /// The chosen store's id; empty for "the one you're in, else the first".
    var storeID: String {
        didSet { UserDefaults.standard.set(storeID, forKey: "currentStoreID") }
    }
    var choosingStore = false

    init() {
        storeID = UserDefaults.standard.string(forKey: "currentStoreID") ?? ""
    }

    func choose(_ store: Store) {
        storeID = store.id?.uuidString ?? ""
        choosingStore = false
    }
}

/// At home the list is in your own order (`HomeOrder`).
extension ListRow: HomeOrderable {
    var homePlace: Double? { entry.homePlace }
    var addedAt: Date? { entry.createdAt }
}
