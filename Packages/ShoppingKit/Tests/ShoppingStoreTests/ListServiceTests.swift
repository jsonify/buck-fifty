#if canImport(CoreData)
import CoreData
import XCTest
import ShoppingCore
@testable import ShoppingStore

/// A list row for `ListOrdering`, as the app makes one.
struct Row: ListSortable {
    var name: String
    var zoneIndex: Int?
    var isChecked: Bool
    var learnedPosition: Double?
    var isWandering = false
    var sortName: String { name }
}

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

    func testRemovingKeepsTheItemAndUndoPutsItBack() throws {
        let store = try makeCostco()
        service.addToList("Eggs", store: store, by: jason)
        let milk = try XCTUnwrap(service.addToList("Milk", store: store, by: partner))
        milk.quantity = 3
        milk.note = "The big one"
        let place = milk.homePlace
        try service.save()

        let removed = try XCTUnwrap(service.remove(milk))
        try service.save()
        XCTAssertEqual(removed.name, "Milk")
        XCTAssertEqual(store.entries.map(\.displayName), ["Eggs"])
        XCTAssertEqual(store.items?.count, 2, "The item stays remembered for Past items")

        let back = try XCTUnwrap(service.restore(removed))
        try service.save()
        XCTAssertEqual(back.displayName, "Milk")
        XCTAssertEqual(back.quantity, 3)
        XCTAssertEqual(back.note, "The big one")
        XCTAssertEqual(back.homePlace, place)
        XCTAssertEqual(back.addedByName, "Sam")
        XCTAssertEqual(store.entries.count, 2)
    }

    func testUndoAfterAddingAgainMergesTheCount() throws {
        let store = try makeCostco()
        let milk = try XCTUnwrap(service.addToList("Milk", store: store, by: jason))
        let removed = try XCTUnwrap(service.remove(milk))
        let again = try XCTUnwrap(service.addToList("Milk", store: store, by: jason))
        XCTAssertEqual(service.restore(removed), again)
        XCTAssertEqual(again.quantity, 2)
        XCTAssertEqual(store.entries.count, 1)
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

    /// Puts `names` on the list, checks them off in that order a minute apart from `start`, and ends the trip.
    func walk(_ names: [String], in store: Store, start: Date, by shopper: Shopper? = nil) throws {
        let who = shopper ?? jason
        for (offset, name) in names.enumerated() {
            let entry = try XCTUnwrap(service.addToList(name, store: store, by: who, now: start))
            service.setChecked(entry, true, by: who, now: start.addingTimeInterval(Double(offset) * 60))
        }
        service.finishTrip(at: store, for: who, now: start.addingTimeInterval(Double(names.count) * 60))
        try service.save()
    }

    /// The list's unchecked entries in list order, with the store's learned positions.
    func listOrder(_ store: Store) -> [String] {
        let zones = store.sortedZones
        let averages = service.zonePositions(in: store)
        let rows = store.entries.map { entry in
            Row(name: entry.displayName, zoneIndex: entry.item?.storeZone.flatMap { zones.firstIndex(of: $0) },
                isChecked: entry.isChecked, learnedPosition: entry.item?.learnedPosition?.doubleValue,
                isWandering: entry.item?.wanders == true)
        }
        var byIndex: [Int: Double] = [:]
        for (index, zone) in zones.enumerated() { byIndex[index] = averages[zone] }
        return ListOrdering.sorted(rows, zoneCount: zones.count, zonePositions: byIndex).map(\.name)
    }

    func testFinishedTripTeachesTheOrderYouWalked() throws {
        let store = try makeCostco()
        let walked = ["Rotisserie chicken", "Eggs", "Coffee", "Batteries"]
        try walk(walked, in: store, start: t0)

        let coffee = try XCTUnwrap(service.item(named: "Coffee", in: store))
        XCTAssertEqual(coffee.learnedPosition?.doubleValue ?? -1, 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(coffee.positionSampleCount, 1)
        XCTAssertEqual(coffee.learned.recent.count, 1)
        XCTAssertNotNil(coffee.learnedTimePosition)

        // Next time they're on the list, in any order, it's the order you walked.
        for name in walked.reversed() { service.addToList(name, store: store, by: jason) }
        XCTAssertEqual(listOrder(store), walked)
    }

    func testATripTeachesOnlyOnce() throws {
        let store = try makeCostco()
        try walk(["Eggs", "Coffee"], in: store, start: t0)
        let trip = try XCTUnwrap(store.trips?.first)
        XCTAssertNotNil(trip.learnedAt)
        XCTAssertEqual(service.learn(from: trip), 0)
        XCTAssertEqual(service.item(named: "Coffee", in: store)?.positionSampleCount, 1)
    }

    func testCheckingEverythingOffAtTheCheckoutTeachesNothing() throws {
        let store = try makeCostco()
        try walk(["Eggs", "Coffee"], in: store, start: t0)
        // The next trip: one thing walked to, then the rest checked off in a burst at the end.
        let names = ["Coffee", "Eggs", "Milk", "Bread"]
        let entries = try names.map { try XCTUnwrap(service.addToList($0, store: store, by: jason)) }
        let start = t0.addingTimeInterval(7 * 24 * 60 * 60)
        service.setChecked(entries[0], true, by: jason, now: start)
        service.setChecked(entries[1], true, by: jason, now: start.addingTimeInterval(600))
        service.setChecked(entries[2], true, by: jason, now: start.addingTimeInterval(600.7))
        service.setChecked(entries[3], true, by: jason, now: start.addingTimeInterval(601.4))
        service.finishTrip(at: store, for: jason, now: start.addingTimeInterval(700))
        try service.save()

        XCTAssertEqual(service.item(named: "Coffee", in: store)?.learnedPosition?.doubleValue, 1)
        XCTAssertEqual(service.item(named: "Eggs", in: store)?.learnedPosition?.doubleValue, 0)
        XCTAssertNil(service.item(named: "Milk", in: store)?.learnedPosition)
        XCTAssertNil(service.item(named: "Bread", in: store)?.learnedPosition)
    }

    func testAnItemNotLearnedYetFollowsItsZonesLearnedItems() throws {
        let store = try makeCostco()
        let zones = store.sortedZones
        try walk(["Steak", "Chicken", "Bread"], in: store, start: t0)
        let meat = zones[4], bakery = zones[7]
        for name in ["Steak", "Chicken"] { service.setZone(meat, for: try XCTUnwrap(service.item(named: name, in: store))) }
        service.setZone(bakery, for: try XCTUnwrap(service.item(named: "Bread", in: store)))
        // Learned: Steak 0, Chicken 0.5, Bread 1; so the meat zone averages 0.25.
        let pork = try XCTUnwrap(service.addToList("Pork", store: store, by: jason))
        service.setZone(meat, for: try XCTUnwrap(pork.item))
        let tv = try XCTUnwrap(service.addToList("TV", store: store, by: jason))
        service.setZone(zones[0], for: try XCTUnwrap(tv.item))
        for name in ["Bread", "Chicken", "Steak", "Pesto"] { service.addToList(name, store: store, by: jason) }

        XCTAssertEqual(service.zonePositions(in: store)[meat] ?? -1, 0.25, accuracy: 1e-9)
        // TV's zone is first in the walk (1/18 of the way) with nothing learned; Pesto has no zone and goes last.
        XCTAssertEqual(listOrder(store), ["Steak", "TV", "Pork", "Chicken", "Bread", "Pesto"])
    }

    // MARK: Zone guesses (issue #4)

    func testANewItemTakesAGuessedZoneOnce() throws {
        let store = try makeCostco()
        let entry = try XCTUnwrap(service.addToList("Kirkland pesto", store: store, by: jason))
        let item = try XCTUnwrap(entry.item)
        XCTAssertTrue(service.needsZoneGuess(item))

        let zone = service.applyZoneGuess("back cooler wall", to: item)
        XCTAssertEqual(zone?.displayName, "Back cooler wall")
        XCTAssertTrue(item.isZoneGuessed)
        XCTAssertFalse(service.needsZoneGuess(item), "A guess is kept: the other phone doesn't guess again")
        XCTAssertNil(service.applyZoneGuess("Bakery", to: item))
        XCTAssertEqual(item.storeZone?.displayName, "Back cooler wall")

        service.confirmZone(of: item)
        XCTAssertEqual(item.zoneSource, ZoneSource.manual)
        XCTAssertFalse(item.isZoneGuessed)
    }

    func testAGuessNeverReplacesAZoneSetByHand() throws {
        let store = try makeCostco()
        let item = try XCTUnwrap(service.addToList("Mystery box", store: store, by: jason)?.item)
        service.setZone(nil, for: item)
        XCTAssertFalse(service.needsZoneGuess(item), "\"No zone\" chosen by hand counts")
        XCTAssertNil(service.applyZoneGuess("Bakery", to: item))
        XCTAssertNil(item.storeZone)
    }

    func testAnAnswerThatIsNotAZoneLeavesTheItemUnzoned() throws {
        let store = try makeCostco()
        let item = try XCTUnwrap(service.addToList("Pesto", store: store, by: jason)?.item)
        XCTAssertNil(service.applyZoneGuess("Garden centre", to: item))
        XCTAssertNil(service.applyZoneGuess(nil, to: item))
        XCTAssertNil(item.storeZone)
        XCTAssertTrue(service.needsZoneGuess(item))
    }

    func testZoneExamplesLeaveOutGuesses() throws {
        let store = try makeCostco()
        let pantry = store.sortedZones[3]
        for name in ["Olive oil", "Coffee"] {
            service.setZone(pantry, for: try XCTUnwrap(service.addToList(name, store: store, by: jason)?.item))
        }
        let guessed = try XCTUnwrap(service.addToList("Pesto", store: store, by: jason)?.item)
        service.applyZoneGuess("Pantry aisles", to: guessed)
        let examples = service.zoneExamples(in: store)
        XCTAssertEqual(examples.map(\.name), DefaultZones.costco)
        XCTAssertEqual(examples[3].items, ["Coffee", "Olive oil"])
        XCTAssertEqual(examples[0].items, [])
    }

    func testLearnedPositionBeatsAGuess() throws {
        let store = try makeCostco()
        let pesto = try XCTUnwrap(service.addToList("Pesto", store: store, by: jason)?.item)
        service.applyZoneGuess("Bakery", to: pesto)   // near the end of the walk
        let tv = try XCTUnwrap(service.addToList("TV", store: store, by: jason)?.item)
        service.setZone(store.sortedZones[0], for: tv)
        XCTAssertEqual(listOrder(store), ["TV", "Pesto"])

        // On the trip, the pesto was grabbed first.
        for entry in store.entries { service.remove(entry) }
        try walk(["Pesto", "TV"], in: store, start: t0)
        for name in ["TV", "Pesto"] { service.addToList(name, store: store, by: jason) }
        XCTAssertEqual(listOrder(store), ["Pesto", "TV"])
    }

    // MARK: Moving by hand

    func testPlacingAnItemByHandRestartsItsSamples() throws {
        let store = try makeCostco()
        try walk(["Eggs", "Coffee", "Milk"], in: store, start: t0)
        let coffee = try XCTUnwrap(service.item(named: "Coffee", in: store))
        let eggs = try XCTUnwrap(service.item(named: "Eggs", in: store))
        service.place([coffee: 0.9, eggs: 0.1], moved: coffee)
        XCTAssertEqual(coffee.learnedPosition?.doubleValue, 0.9)
        XCTAssertEqual(coffee.learned.recent, [0.9])
        XCTAssertEqual(eggs.learnedPosition?.doubleValue, 0.1)
        XCTAssertEqual(eggs.learned.recent, [0], "A neighbour keeps what trips taught it")
    }

    // MARK: The floor plan (issue #5)

    func testAnItemsSpotIsTheMedianOfItsRecentPoints() throws {
        let store = try makeCostco()
        let points = [FloorPoint(x: 10, y: 20), FloorPoint(x: 11, y: 21), FloorPoint(x: 40, y: 2)]
        for (n, point) in points.enumerated() {
            let entry = try XCTUnwrap(service.addToList("Coffee", store: store, by: jason))
            let start = t0.addingTimeInterval(Double(n) * 86_400)
            let checkOff = try XCTUnwrap(service.setChecked(entry, true, by: jason, now: start))
            service.setPoint(point, of: checkOff)
            service.finishTrip(at: store, for: jason, now: start.addingTimeInterval(60))
        }
        let coffee = try XCTUnwrap(service.item(named: "Coffee", in: store))
        XCTAssertEqual(service.spot(of: coffee), FloorPoint(x: 11, y: 20))
        XCTAssertEqual(service.landmark(of: coffee), FloorPoint(x: 11, y: 20), "Two of three agree: it has settled")

        let tea = try XCTUnwrap(service.addToList("Tea", store: store, by: jason)?.item)
        XCTAssertNil(service.spot(of: tea))
    }

    func testRecordingAMappedTrip() throws {
        let store = try makeCostco()
        let eggs = try XCTUnwrap(service.addToList("Eggs", store: store, by: jason))
        let milk = try XCTUnwrap(service.addToList("Milk", store: store, by: jason))
        let a = try XCTUnwrap(service.setChecked(eggs, true, by: jason, now: t0))
        let b = try XCTUnwrap(service.setChecked(milk, true, by: jason, now: t0.addingTimeInterval(60)))
        let trip = try XCTUnwrap(service.currentTrip(at: store, for: jason, now: t0.addingTimeInterval(61)))
        service.setChecked(milk, false, by: jason, now: t0.addingTimeInterval(70))   // a mis-tap: no point for it
        XCTAssertNil(service.setChecked(milk, false, by: jason, now: t0.addingTimeInterval(71)))

        let walk = [FloorPoint.entrance, FloorPoint(x: 0, y: 10), FloorPoint(x: 5, y: 10)]
        service.recordPath(walk, points: [a: FloorPoint(x: 0, y: 10), b: FloorPoint(x: 5, y: 10)], of: trip)
        XCTAssertEqual(a.floorPoint, FloorPoint(x: 0, y: 10))
        XCTAssertEqual(trip.floorPath, walk)
        service.finishTrip(at: store, for: jason, now: t0.addingTimeInterval(120))
        try service.save()

        XCTAssertEqual(service.lastMappedTrip(at: store), trip)
        XCTAssertEqual(service.checkoutSpot(in: store), FloorPoint(x: 5, y: 10))
    }

    // MARK: Remembered items, after Done

    func testTheLastTripIsStillThereAfterDone() throws {
        let store = try makeCostco()
        try walk(["Batteries", "Coffee", "Eggs"], in: store, start: t0)
        try walk(["Milk", "Bread", "Milk"], in: store, start: t0.addingTimeInterval(86_400))
        XCTAssertTrue(store.entries.isEmpty, "Done takes what was bought off the list")

        let trip = try XCTUnwrap(service.lastTrip(at: store))
        XCTAssertEqual(service.items(boughtOn: trip).map(\.displayName), ["Milk", "Bread"])
        XCTAssertEqual(store.items?.count, 5, "Everything bought is still remembered")
        let coffee = try XCTUnwrap(service.item(named: "Coffee", in: store))
        XCTAssertNotNil(coffee.learnedPosition, "and where it was grabbed")
        XCTAssertFalse(service.isOnList(coffee))
        service.addToList("Coffee", store: store, by: jason)
        XCTAssertTrue(service.isOnList(coffee))
    }

    func testNoLastTripWithoutCheckOffs() throws {
        let store = try makeCostco()
        service.startTrip(at: store, for: jason, now: t0)
        service.finishTrip(at: store, for: jason, now: t0.addingTimeInterval(60))
        XCTAssertNil(service.lastTrip(at: store))
    }

    func testRenamingARememberedItem() throws {
        let store = try makeCostco()
        let coffee = try XCTUnwrap(service.addToList("Cofee", store: store, by: jason)?.item)
        service.addToList("Tea", store: store, by: jason)
        XCTAssertTrue(service.renameItem(coffee, to: "  coffee beans "))
        XCTAssertEqual(coffee.displayName, "coffee beans")
        XCTAssertEqual(service.item(named: "Coffee Beans", in: store), coffee)
        XCTAssertFalse(service.renameItem(coffee, to: "TEA"), "Another item already has that name")
        XCTAssertFalse(service.renameItem(coffee, to: "   "))
        XCTAssertEqual(coffee.displayName, "coffee beans")
    }

    func testForgettingAnItem() throws {
        let store = try makeCostco()
        try walk(["Eggs", "Coffee"], in: store, start: t0)
        let coffee = try XCTUnwrap(service.item(named: "Coffee", in: store))
        service.addToList("Coffee", store: store, by: jason)
        service.forget(coffee)
        try service.save()
        XCTAssertNil(service.item(named: "Coffee", in: store))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(service.lastTrip(at: store).map { service.items(boughtOn: $0).map(\.displayName) }, ["Eggs"])
    }

    func testReplacingZonesKeepsTheOnesThatMatch() throws {
        let store = try makeCostco()
        let meat = store.sortedZones[4]
        let steak = try XCTUnwrap(service.addToList("Steak", store: store, by: jason)?.item)
        service.setZone(meat, for: steak)
        let towels = try XCTUnwrap(service.addToList("Paper towels", store: store, by: jason)?.item)
        service.setZone(store.sortedZones[2], for: towels)   // "Paper goods", which goes away

        service.replaceZones(of: store, with: DefaultZones.costcoAuroraVillage)
        try service.save()

        XCTAssertEqual(store.sortedZones.map(\.displayName), DefaultZones.costcoAuroraVillage)
        XCTAssertEqual(store.sortedZones.map(\.sortIndex), (0..<21).map { Int64($0) })
        XCTAssertEqual(steak.storeZone, meat, "Meat is in both, so it stays, with its items")
        XCTAssertEqual(meat.sortIndex, 6)
        XCTAssertNil(towels.storeZone)
        XCTAssertTrue(service.needsZoneGuess(towels), "An item whose zone went away can be guessed again")
    }

    func testReplacingZonesSkipsBlanksAndRepeats() throws {
        let store = service.createStore(named: "Corner shop", zoneNames: ["A"])
        service.replaceZones(of: store, with: ["  b ", "B", "", "a", "C"])
        XCTAssertEqual(store.sortedZones.map(\.displayName), ["b", "a", "C"])
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
