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

    func testLeavingEndsTheTrip() {
        XCTAssertEqual(LocationTrips.action(for: .left, hasOpenTrip: true, itemsLeft: 2), .endTrip)
        XCTAssertEqual(LocationTrips.action(for: .left, hasOpenTrip: false, itemsLeft: 2), .nothing)
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
