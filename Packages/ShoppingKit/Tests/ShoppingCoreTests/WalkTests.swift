import XCTest
@testable import ShoppingCore

final class WalkTests: XCTestCase {
    private let zones = ["Entrance", "Pantry", "Meat"]

    private func list(checked: Set<String> = []) -> [Entry] {
        [
            Entry(sortName: "Steak", zoneIndex: 2),
            Entry(sortName: "Batteries", zoneIndex: 0),
            Entry(sortName: "Rice", zoneIndex: 1),
            Entry(sortName: "Oil", zoneIndex: 1),
            Entry(sortName: "Pesto", zoneIndex: nil),
            Entry(sortName: "Advent calendar", zoneIndex: 1, isWandering: true),
        ].map { entry in
            var entry = entry
            entry.isChecked = checked.contains(entry.sortName)
            return entry
        }
    }

    private func numbered(_ stops: [Walk.Stop<Entry>]) -> [String: Int] {
        var result: [String: Int] = [:]
        for stop in stops {
            for (entry, number) in zip(stop.entries, stop.numbers) {
                if let number { result[entry.sortName] = number }
            }
        }
        return result
    }

    func testStopsFollowTheWalkWithLookForItFirstAndUnnumbered() {
        let stops = Walk.stops(list(), zoneNames: zones)
        XCTAssertEqual(stops.map(\.title), [ListOrdering.lookForItTitle, "Entrance", "Pantry", "Meat",
                                            ListOrdering.unzonedTitle])
        XCTAssertEqual(stops[0].numbers, [nil])
        XCTAssertFalse(stops[0].isInWalk)
        XCTAssertEqual(numbered(stops), ["Batteries": 1, "Oil": 2, "Rice": 3, "Steak": 4, "Pesto": 5])
    }

    func testCheckingOffKeepsEveryNumberAndPlace() {
        let before = Walk.stops(list(), zoneNames: zones)
        let after = Walk.stops(list(checked: ["Batteries", "Oil"]), zoneNames: zones)
        XCTAssertEqual(numbered(before), numbered(after))
        // Checked items stay in their zone rather than moving to In the cart.
        XCTAssertEqual(after.map(\.title), before.map(\.title))
        XCTAssertEqual(after[2].entries.map(\.sortName), ["Oil", "Rice"])
        XCTAssertEqual(after[2].left, 1)
    }

    func testDoneNextAndAhead() {
        let stops = Walk.stops(list(checked: ["Batteries", "Oil"]), zoneNames: zones)
        XCTAssertEqual(stops.map(\.state), [.ahead, .done, .next, .ahead, .ahead])
        let next = Walk.next(in: stops)
        XCTAssertEqual(next?.entry.sortName, "Rice")
        XCTAssertEqual(next?.number, 3)
    }

    func testAllCheckedHasNoNext() {
        let all = Set(list().map(\.sortName))
        let stops = Walk.stops(list(checked: all), zoneNames: zones)
        XCTAssertTrue(stops.allSatisfy { $0.state == .done })
        XCTAssertNil(Walk.next(in: stops))
    }

    func testLearnedPositionsDecideTheNumbers() {
        var entries = list()
        // The steak was found right by the door on the last trips.
        entries[0].learnedPosition = 0.01
        let stops = Walk.stops(entries, zoneNames: zones)
        XCTAssertEqual(numbered(stops)["Steak"], 1)
        XCTAssertEqual(numbered(stops)["Batteries"], 2)
    }
}
