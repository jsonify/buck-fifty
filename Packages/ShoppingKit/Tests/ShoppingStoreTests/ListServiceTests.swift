#if canImport(CoreData)
import CoreData
import XCTest
import ShoppingCore
@testable import ShoppingStore

final class ListServiceTests: XCTestCase {
    var persistence: Persistence!
    var service: ListService!
    let jason = Shopper(id: "jason-id", name: "Jason")
    let partner = Shopper(id: "partner-id", name: "Sam")
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        persistence = try Persistence(.inMemory)
        service = ListService(context: persistence.viewContext, policy: TripPolicy(quietPeriod: 45 * 60))
    }

    func makeCostco() throws -> Store {
        let store = service.createStore(named: "Costco", now: t0)
        try service.save()
        return store
    }

    func testNewCostcoGetsWalkingOrderZones() throws {
        let store = try makeCostco()
        XCTAssertEqual(store.sortedZones.map(\.displayName), DefaultZones.costco)
    }

    func testAddingRemembersItemsAndMergesRepeats() throws {
        let store = try makeCostco()
        let first = try XCTUnwrap(service.addToList("  Olive   oil ", store: store, by: jason))
        XCTAssertEqual(first.displayName, "Olive oil")
        XCTAssertEqual(first.addedByName, "Jason")

        let again = try XCTUnwrap(service.addToList("olive OIL", store: store, by: partner))
        XCTAssertEqual(again, first)
        XCTAssertEqual(again.quantity, 2)
        XCTAssertEqual(store.items?.count, 1)
        XCTAssertNil(service.addToList("   ", store: store, by: jason))
    }

    func testRememberedItemKeepsItsZone() throws {
        let store = try makeCostco()
        let entry = try XCTUnwrap(service.addToList("Rotisserie chicken", store: store, by: jason))
        let corner = try XCTUnwrap(store.sortedZones.last)
        service.setZone(corner, for: try XCTUnwrap(entry.item))
        XCTAssertEqual(entry.item?.zoneSource, "manual")
        service.setChecked(entry, true, by: jason, now: t0)
        service.finishTrip(at: store, for: jason, now: t0.addingTimeInterval(60))
        try service.save()

        let next = try XCTUnwrap(service.addToList("rotisserie chicken", store: store, by: jason))
        XCTAssertEqual(next.item?.storeZone, corner)
    }

    func testSuggestions() throws {
        let store = try makeCostco()
        for name in ["Paper towels", "Kirkland paper towels", "Peanut butter"] {
            service.addToList(name, store: store, by: jason)
        }
        XCTAssertEqual(service.suggestions(for: "pa", in: store).map(\.displayName),
                       ["Paper towels", "Kirkland paper towels"])
    }

    func testCheckOffStartsTripAndRecordsTimestampedRoute() throws {
        let store = try makeCostco()
        let eggs = try XCTUnwrap(service.addToList("Eggs", store: store, by: jason))
        let coffee = try XCTUnwrap(service.addToList("Coffee", store: store, by: jason))
        XCTAssertNil(service.currentTrip(at: store, for: jason, now: t0))

        service.setChecked(coffee, true, by: jason, now: t0)
        service.setChecked(eggs, true, by: jason, now: t0.addingTimeInterval(300))
        let trip = try XCTUnwrap(service.currentTrip(at: store, for: jason, now: t0.addingTimeInterval(301)))
        XCTAssertEqual(trip.shopperName, "Jason")
        XCTAssertEqual(service.route(of: trip).map { $0.item?.displayName }, ["Coffee", "Eggs"])
        XCTAssertEqual(service.route(of: trip).map(\.timestamp), [t0, t0.addingTimeInterval(300)])
        XCTAssertEqual(coffee.checkedByName, "Jason")
    }

    func testUncheckingDuringTripRemovesTheCheckOff() throws {
        let store = try makeCostco()
        let eggs = try XCTUnwrap(service.addToList("Eggs", store: store, by: jason))
        service.setChecked(eggs, true, by: jason, now: t0)
        service.setChecked(eggs, false, by: jason, now: t0.addingTimeInterval(5))
        let trip = try XCTUnwrap(service.currentTrip(at: store, for: jason, now: t0.addingTimeInterval(6)))
        XCTAssertTrue(service.route(of: trip).isEmpty)
        XCTAssertFalse(eggs.isChecked)
        XCTAssertNil(eggs.checkedByID)
    }

    func testFinishingTripClearsWhatThatShopperBought() throws {
        let store = try makeCostco()
        let eggs = try XCTUnwrap(service.addToList("Eggs", store: store, by: jason))
        let milk = try XCTUnwrap(service.addToList("Milk", store: store, by: jason))
        let bread = try XCTUnwrap(service.addToList("Bread", store: store, by: jason))
        service.setChecked(eggs, true, by: jason, now: t0)
        service.setChecked(milk, true, by: partner, now: t0)
        service.finishTrip(at: store, for: jason, now: t0.addingTimeInterval(600))
        try service.save()

        XCTAssertTrue(eggs.isDeleted || eggs.managedObjectContext == nil)
        XCTAssertEqual(Set(store.entries.map(\.displayName)), ["Milk", "Bread"])
        XCTAssertTrue(milk.isChecked)
        XCTAssertFalse(bread.isChecked)
        XCTAssertNil(service.currentTrip(at: store, for: jason, now: t0.addingTimeInterval(601)))
        XCTAssertNotNil(service.currentTrip(at: store, for: partner, now: t0.addingTimeInterval(601)))
        XCTAssertEqual(store.items?.count, 3, "Bought items stay remembered")
    }

    func testTwoShoppersAtOnceMakeTwoTrips() throws {
        let store = try makeCostco()
        let a = try XCTUnwrap(service.addToList("Eggs", store: store, by: jason))
        let b = try XCTUnwrap(service.addToList("Milk", store: store, by: jason))
        service.setChecked(a, true, by: jason, now: t0)
        service.setChecked(b, true, by: partner, now: t0.addingTimeInterval(1))
        let mine = try XCTUnwrap(service.currentTrip(at: store, for: jason, now: t0.addingTimeInterval(2)))
        let theirs = try XCTUnwrap(service.currentTrip(at: store, for: partner, now: t0.addingTimeInterval(2)))
        XCTAssertNotEqual(mine, theirs)
        XCTAssertEqual(service.route(of: mine).map { $0.item?.displayName }, ["Eggs"])
        XCTAssertEqual(service.route(of: theirs).map { $0.item?.displayName }, ["Milk"])
    }

    func testQuietTripEndsAtItsLastActivity() throws {
        let store = try makeCostco()
        let eggs = try XCTUnwrap(service.addToList("Eggs", store: store, by: jason))
        service.setChecked(eggs, true, by: jason, now: t0)
        let trip = try XCTUnwrap(service.currentTrip(at: store, for: jason, now: t0))
        XCTAssertNil(service.currentTrip(at: store, for: jason, now: t0.addingTimeInterval(46 * 60)))
        XCTAssertEqual(trip.endedAt, t0)
        XCTAssertTrue(store.entries.isEmpty, "What was checked off on the ended trip is bought")
    }

    func testZonesReorderAddAndDelete() throws {
        let store = service.createStore(named: "Corner shop", zoneNames: ["A", "B", "C"])
        service.moveZone(in: store, from: 2, to: 0)
        XCTAssertEqual(store.sortedZones.map(\.displayName), ["C", "A", "B"])
        service.addZone(named: "D", to: store)
        XCTAssertEqual(store.sortedZones.map(\.displayName), ["C", "A", "B", "D"])

        let entry = try XCTUnwrap(service.addToList("Thing", store: store, by: jason))
        let a = store.sortedZones[1]
        service.setZone(a, for: try XCTUnwrap(entry.item))
        service.deleteZone(a)
        try service.save()
        XCTAssertEqual(store.sortedZones.map(\.displayName), ["C", "B", "D"])
        XCTAssertEqual(store.sortedZones.map(\.sortIndex), [0, 1, 2])
        XCTAssertNil(entry.item?.storeZone)
    }

    func testRenameOntoAnExistingItemMovesTheEntry() throws {
        let store = try makeCostco()
        let towels = try XCTUnwrap(service.addToList("Paper towels", store: store, by: jason))
        service.setChecked(towels, true, by: jason, now: t0)
        service.finishTrip(at: store, for: jason, now: t0)
        let typo = try XCTUnwrap(service.addToList("Papr towels", store: store, by: jason))
        let item = service.rename(typo, to: "paper towels")
        XCTAssertEqual(item?.displayName, "Paper towels")
        XCTAssertEqual(typo.item, item)
    }

    /// Objects added to a list are put in the persistent store the list lives in: a shared list lives in the shared
    /// CloudKit store, and an item added to it in the private one would never reach the other person.
    func testNewObjectsGoToTheStoresPersistentStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = NSPersistentContainer(name: "Two", managedObjectModel: ShoppingModel.model)
        container.persistentStoreDescriptions = ["private", "shared"].map {
            NSPersistentStoreDescription(url: directory.appendingPathComponent("\($0).sqlite"))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var loadError: Error?
        container.loadPersistentStores { _, error in if let error { loadError = error } }
        if let loadError { throw loadError }
        let shared = try XCTUnwrap(container.persistentStoreCoordinator.persistentStores.last)

        let context = container.viewContext
        let service = ListService(context: context)
        let store = service.createStore(named: "Costco")
        context.assign(store, to: shared)
        for zone in store.zones ?? [] { context.assign(zone, to: shared) }
        try context.save()

        let entry = try XCTUnwrap(service.addToList("Eggs", store: store, by: jason))
        service.setChecked(entry, true, by: jason)
        try context.save()
        let trip = try XCTUnwrap(service.currentTrip(at: store, for: jason))
        for object in [entry, try XCTUnwrap(entry.item), trip] as [NSManagedObject] {
            XCTAssertEqual(object.objectID.persistentStore, shared, "\(object.entity.name ?? "?")")
        }
    }
}
#endif
