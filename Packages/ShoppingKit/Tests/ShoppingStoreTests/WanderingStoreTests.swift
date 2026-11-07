#if canImport(CoreData)
import CoreData
import XCTest
import ShoppingCore
@testable import ShoppingStore

/// Wandering items through real trips (issue #8).
extension ListServiceTests {
    /// A trip a week after `t0` × `week`, with `item` checked off at `rank` among four others.
    func shopTrip(week: Double, item: String, at rank: Int, in store: Store) throws {
        var names = ["Bananas", "Paper towels", "Eggs", "Milk"]
        names.insert(item, at: rank)
        try walk(names, in: store, start: t0.addingTimeInterval(week * 7 * 24 * 60 * 60))
    }

    func testAnItemFoundAllOverTheStoreWandersAndSettlesAgain() throws {
        let store = try makeCostco()
        // Front, back, middle: wandering after the third trip.
        try shopTrip(week: 0, item: "Pumpkin pie", at: 0, in: store)
        try shopTrip(week: 1, item: "Pumpkin pie", at: 4, in: store)
        let pie = try XCTUnwrap(service.item(named: "Pumpkin pie", in: store))
        XCTAssertFalse(pie.isWandering, "Two trips aren't enough")
        try shopTrip(week: 2, item: "Pumpkin pie", at: 2, in: store)
        XCTAssertTrue(pie.isWandering)
        XCTAssertTrue(pie.wanders)
        XCTAssertEqual(service.wanderNote(for: pie), "Seen anywhere from 0% to 100% of the way in, last at 50%")
        XCTAssertFalse(try XCTUnwrap(service.item(named: "Eggs", in: store)).isWandering)

        // On the list it's at the top, under Look for it.
        for name in ["Milk", "Bananas", "Pumpkin pie"] { service.addToList(name, store: store, by: jason) }
        XCTAssertEqual(listOrder(store), ["Pumpkin pie", "Bananas", "Milk"])
        for entry in store.entries { service.remove(entry) }

        // It settles in the middle: the trip that flagged it and two more agree, so it's back in the walk.
        try shopTrip(week: 3, item: "Pumpkin pie", at: 2, in: store)
        XCTAssertTrue(pie.isWandering)
        try shopTrip(week: 4, item: "Pumpkin pie", at: 2, in: store)
        XCTAssertFalse(pie.isWandering)
        XCTAssertFalse(pie.wanders)
        // Still learning all along.
        XCTAssertEqual(pie.positionSampleCount, 5)
    }

    func testMovingOnceDoesNotWander() throws {
        let store = try makeCostco()
        for week in 0..<3 { try shopTrip(week: Double(week), item: "Coffee", at: 0, in: store) }
        for week in 3..<6 { try shopTrip(week: Double(week), item: "Coffee", at: 4, in: store) }
        let coffee = try XCTUnwrap(service.item(named: "Coffee", in: store))
        XCTAssertFalse(coffee.isWandering)
        XCTAssertEqual(coffee.learnedPosition?.doubleValue ?? -1, 1, accuracy: 0.05)
    }

    func testSpotSetByHandBeatsTheTrips() throws {
        let store = try makeCostco()
        let entry = try XCTUnwrap(service.addToList("Patio umbrella", store: store, by: jason))
        let umbrella = try XCTUnwrap(entry.item)
        XCTAssertFalse(umbrella.wanders)
        service.setWanderOverride(.wanders, for: umbrella)
        try service.save()
        XCTAssertEqual(umbrella.wanderOverride, "wanders")
        XCTAssertTrue(umbrella.wanders, "Flagged by hand before any trip")
        XCTAssertNil(service.wanderNote(for: umbrella))

        try shopTrip(week: 0, item: "Pumpkin pie", at: 0, in: store)
        try shopTrip(week: 1, item: "Pumpkin pie", at: 4, in: store)
        try shopTrip(week: 2, item: "Pumpkin pie", at: 2, in: store)
        let pie = try XCTUnwrap(service.item(named: "Pumpkin pie", in: store))
        XCTAssertTrue(pie.isWandering)
        service.setWanderOverride(.fixed, for: pie)
        XCTAssertFalse(pie.wanders, "A fixed spot keeps it in the walk")
        XCTAssertTrue(pie.isWandering, "The trips' answer is kept for when the override goes")
        service.setWanderOverride(nil, for: pie)
        XCTAssertTrue(pie.wanders)
    }

    func testWanderingItemsAreLeftOutOfTheirZonesAverage() throws {
        let store = try makeCostco()
        let zone = try XCTUnwrap(store.sortedZones.first)
        try shopTrip(week: 0, item: "Steak", at: 1, in: store)
        let steak = try XCTUnwrap(service.item(named: "Steak", in: store))
        let paper = try XCTUnwrap(service.item(named: "Paper towels", in: store))
        service.setZone(zone, for: steak)
        service.setZone(zone, for: paper)
        let both = try XCTUnwrap(service.zonePositions(in: store)[zone])
        service.setWanderOverride(.wanders, for: steak)
        let withoutSteak = try XCTUnwrap(service.zonePositions(in: store)[zone])
        XCTAssertNotEqual(both, withoutSteak)
        XCTAssertEqual(withoutSteak, paper.learnedPosition?.doubleValue ?? -1, accuracy: 1e-9)
    }
}
#endif
