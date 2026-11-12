import XCTest
@testable import ShoppingCore

final class HomeListTests: XCTestCase {
    private struct Line: HomeOrderable {
        var sortName: String
        var homePlace: Double?
        var addedAt: Date?
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testHomeOrderGoesByPlaceThenWhenAdded() {
        let lines = [
            Line(sortName: "Milk", homePlace: 2, addedAt: t0),
            Line(sortName: "Old one", homePlace: nil, addedAt: t0.addingTimeInterval(-60)),
            Line(sortName: "Eggs", homePlace: 0, addedAt: t0.addingTimeInterval(60)),
            Line(sortName: "Bread", homePlace: 1, addedAt: t0.addingTimeInterval(120)),
            Line(sortName: "Older one", homePlace: nil, addedAt: t0.addingTimeInterval(-120)),
        ]
        XCTAssertEqual(HomeOrder.sorted(lines).map(\.sortName), ["Eggs", "Bread", "Milk", "Older one", "Old one"])
    }

    func testSomethingNewGoesAtTheBottom() {
        XCTAssertEqual(HomeOrder.next(after: []), 0)
        XCTAssertEqual(HomeOrder.next(after: [nil, 3, 1]), 4)
    }

    func testAMoveRenumbersEveryone() {
        // A B C D, C dragged to the top: C A B D.
        XCTAssertEqual(HomeOrder.afterMove(count: 4, from: 2, to: 0), [2: 0, 0: 1, 1: 2, 3: 3])
        // A dragged to the bottom: B C D A.
        XCTAssertEqual(HomeOrder.afterMove(count: 4, from: 0, to: 3), [1: 0, 2: 1, 3: 2, 0: 3])
        XCTAssertEqual(HomeOrder.afterMove(count: 4, from: 1, to: 1), [:])
        XCTAssertEqual(HomeOrder.afterMove(count: 2, from: 0, to: 5), [:])
    }

    private func past(_ name: String, times: Int, daysAgo: Double? = nil, low: Bool = false,
                      lastTrip: Bool = false) -> PastItem<String> {
        PastItem(ref: name, name: name, timesBought: times,
                 lastBought: daysAgo.map { t0.addingTimeInterval(-$0 * 86_400) }, isRunningLow: low,
                 boughtLastTrip: lastTrip, isOnList: false)
    }

    func testPastItemsFilters() {
        let items = [
            past("Toilet paper", times: 4, daysAgo: 30),
            past("Milk", times: 9, daysAgo: 7, low: true, lastTrip: true),
            past("Eggs", times: 9, daysAgo: 3, lastTrip: true),
            past("Dish soap", times: 2, daysAgo: 40, low: true),
            past("Chickpeas", times: 0),
        ]
        func names(_ filter: PastItemsFilter, _ query: String = "") -> [String] {
            PastItems.filtered(items, by: filter, query: query).map(\.name)
        }
        // Most bought first; a tie goes to the more recent.
        XCTAssertEqual(names(.usual), ["Eggs", "Milk", "Toilet paper", "Dish soap"])
        XCTAssertEqual(names(.runningLow), ["Milk", "Dish soap"])
        XCTAssertEqual(names(.lastTrip), ["Eggs", "Milk"])
        XCTAssertEqual(names(.alphabetical), ["Chickpeas", "Dish soap", "Eggs", "Milk", "Toilet paper"])
        XCTAssertEqual(names(.alphabetical, "  PAPER "), ["Toilet paper"])
    }

    func testPastItemSummary() {
        let calendar = Calendar(identifier: .gregorian)
        XCTAssertEqual(PastItems.summary(past("Chickpeas", times: 0), now: t0, calendar: calendar), "Not bought yet")
        XCTAssertEqual(PastItems.summary(past("Milk", times: 1, daysAgo: 1), now: t0, calendar: calendar),
                       "Bought once, yesterday")
        XCTAssertEqual(PastItems.summary(past("Eggs", times: 9, daysAgo: 3), now: t0, calendar: calendar),
                       "Bought 9 times · last 3 days ago")
    }
}
