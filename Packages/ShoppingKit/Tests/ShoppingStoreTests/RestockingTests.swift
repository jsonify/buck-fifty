#if canImport(CoreData)
import CoreData
import XCTest
import ShoppingCore
@testable import ShoppingStore

final class RestockingTests: XCTestCase {
    var persistence: Persistence!
    var service: ListService!
    let jason = Shopper(id: "jason-id", name: "Jason")
    let day: TimeInterval = 24 * 60 * 60
    let now = Date(timeIntervalSince1970: 1_699_876_800)
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    override func setUpWithError() throws {
        persistence = try Persistence(.inMemory)
        service = ListService(context: persistence.viewContext)
    }

    /// A trip `daysAgo` that buys `names`, a minute apart.
    func shop(_ names: [String], daysAgo: Double, at store: Store) {
        let start = now.addingTimeInterval(-daysAgo * day)
        for (i, name) in names.enumerated() {
            guard let entry = service.addToList(name, store: store, by: jason, now: start) else { continue }
            service.setChecked(entry, true, by: jason, now: start.addingTimeInterval(Double(i) * 60))
        }
        service.finishTrip(at: store, for: jason, now: start.addingTimeInterval(Double(names.count) * 60))
    }

    func testRestockLinesSortNeededFirst() throws {
        let store = service.createStore(named: "Costco", now: now)
        // Weekly trips; milk every time, paper towels every other, olive oil once.
        shop(["Milk", "Paper towels", "Olive oil"], daysAgo: 21, at: store)
        shop(["Milk"], daysAgo: 14, at: store)
        shop(["Milk", "Paper towels"], daysAgo: 7, at: store)
        try service.save()

        let rhythm = service.rhythm(of: store, calendar: calendar)
        XCTAssertEqual(rhythm.interval, 7 * day)

        let lines = service.restockLines(in: store, now: now, calendar: calendar)
        XCTAssertEqual(lines.map(\.item.displayName), ["Milk", "Paper towels", "Olive oil"])
        XCTAssertEqual(lines[0].shelf, .needed)
        XCTAssertEqual(lines[1].shelf, .soon)
        XCTAssertEqual(lines[2].shelf, .rest)
        XCTAssertEqual(lines[0].summary(now: now, calendar: calendar), "Every week · last 7 days ago")
        XCTAssertEqual(lines[2].summary(now: now, calendar: calendar), "Bought once, 21 days ago")
        XCTAssertTrue(lines.allSatisfy { !$0.isOnList })
    }

    func testAddNeededAndToggle() throws {
        let store = service.createStore(named: "Costco", now: now)
        shop(["Milk", "Eggs"], daysAgo: 14, at: store)
        shop(["Milk", "Eggs"], daysAgo: 7, at: store)
        try service.save()

        XCTAssertEqual(service.neededNotOnList(in: store, now: now, calendar: calendar).count, 2)
        XCTAssertEqual(service.addNeeded(in: store, by: jason, now: now, calendar: calendar), 2)
        XCTAssertEqual(store.remainingCount, 2)
        XCTAssertEqual(service.neededNotOnList(in: store, now: now, calendar: calendar).count, 0)

        let milk = try XCTUnwrap(service.item(named: "milk", in: store))
        XCTAssertFalse(service.toggleOnList(milk, by: jason, now: now))
        XCTAssertEqual(store.remainingCount, 1)
        XCTAssertTrue(service.toggleOnList(milk, by: jason, now: now))
        XCTAssertEqual(store.remainingCount, 2)
    }

    func testOpenTripsDontCountAsPurchases() throws {
        let store = service.createStore(named: "Costco", now: now)
        let entry = try XCTUnwrap(service.addToList("Milk", store: store, by: jason, now: now))
        service.setChecked(entry, true, by: jason, now: now)
        let milk = try XCTUnwrap(entry.item)
        XCTAssertEqual(service.purchaseDates(of: milk), [])
        XCTAssertEqual(service.tripDates(at: store), [])
    }
}
#endif
