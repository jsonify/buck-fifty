import XCTest
@testable import ShoppingCore

final class LocationTripsTests: XCTestCase {
    func testArrivingWithSomethingOnTheListStartsATrip() {
        XCTAssertEqual(LocationTrips.action(for: .arrived, hasOpenTrip: false, itemsLeft: 3), .startTrip)
    }

    func testArrivingWithAnEmptyListDoesNothing() {
        XCTAssertEqual(LocationTrips.action(for: .arrived, hasOpenTrip: false, itemsLeft: 0), .nothing)
    }

    func testArrivingDuringATripKeepsIt() {
        XCTAssertEqual(LocationTrips.action(for: .arrived, hasOpenTrip: true, itemsLeft: 3), .nothing)
    }

    func testLeavingStartsTheLeaveGrace() {
        XCTAssertEqual(LocationTrips.action(for: .left, hasOpenTrip: true, itemsLeft: 2), .leaving)
        XCTAssertEqual(LocationTrips.action(for: .left, hasOpenTrip: false, itemsLeft: 2), .nothing)
    }

    func testALeaveIsDueOnlyAfterTheGrace() {
        let out = Date(timeIntervalSince1970: 1_000_000)
        var leaves = PendingLeaves()
        leaves.left("costco", at: out)
        XCTAssertTrue(leaves.due(now: out.addingTimeInterval(LocationTrips.leaveGrace - 1)).isEmpty)
        XCTAssertEqual(leaves.due(now: out.addingTimeInterval(LocationTrips.leaveGrace)), ["costco": out])
    }

    func testComingBackInCancelsTheLeave() {
        // The phone's location wandered out of the circle at the back of a big store, then back in.
        let out = Date(timeIntervalSince1970: 1_000_000)
        var leaves = PendingLeaves()
        leaves.left("costco", at: out)
        leaves.cancel("costco")
        XCTAssertTrue(leaves.due(now: out.addingTimeInterval(LocationTrips.leaveGrace * 3)).isEmpty)
    }

    func testASecondLeaveKeepsTheFirstTime() {
        let out = Date(timeIntervalSince1970: 1_000_000)
        var leaves = PendingLeaves()
        leaves.left("costco", at: out)
        leaves.left("costco", at: out.addingTimeInterval(120))
        XCTAssertEqual(leaves.leftAt["costco"], out)
    }

    func testLeavesRoundTrip() {
        var leaves = PendingLeaves()
        leaves.left("a", at: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(PendingLeaves.decode(PendingLeaves.encode(leaves)), leaves)
        XCTAssertEqual(PendingLeaves.decode(Data("nope".utf8)), PendingLeaves())
    }

    func testPinsRoundTrip() {
        let pins = ["a": StorePin(latitude: 47.77, longitude: -122.34),
                    "b": StorePin(latitude: 1, longitude: 2, radius: 400)]
        XCTAssertEqual(StorePin.decode(StorePin.encode(pins)), pins)
        XCTAssertEqual(pins["a"]?.radius, StorePin.defaultRadius)
    }

    func testUnreadablePinsAreEmpty() {
        XCTAssertTrue(StorePin.decode(nil).isEmpty)
        XCTAssertTrue(StorePin.decode(Data("nope".utf8)).isEmpty)
    }
}
