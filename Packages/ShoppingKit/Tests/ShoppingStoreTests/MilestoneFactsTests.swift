#if canImport(CoreData)
import CoreData
import XCTest
import ShoppingCore
@testable import ShoppingStore

final class MilestoneFactsTests: XCTestCase {
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

    func shop(_ names: [String], daysAgo: Double, at store: Store) {
        let start = now.addingTimeInterval(-daysAgo * day)
        for (i, name) in names.enumerated() {
            guard let entry = service.addToList(name, store: store, by: jason, now: start) else { continue }
            service.setChecked(entry, true, by: jason, now: start.addingTimeInterval(Double(i) * 60))
        }
        service.finishTrip(at: store, for: jason, now: start.addingTimeInterval(Double(names.count) * 60))
    }

    func testFactsComeFromTheStoresTrips() throws {
        let store = service.createStore(named: "Costco", now: now)
        XCTAssertEqual(service.milestoneFacts(for: store, mapsStore: false, isShared: false, tried: [],
                                              calendar: calendar), MilestoneFacts())
        shop(["Milk", "Eggs"], daysAgo: 14, at: store)
        // One check-off teaches nothing, but it's still a day shopped and a purchase.
        shop(["Milk"], daysAgo: 7, at: store)
        try service.save()

        let facts = service.milestoneFacts(for: store, mapsStore: true, isShared: true, tried: ["drag"],
                                           calendar: calendar)
        XCTAssertEqual(facts.teachingTrips, 1)
        XCTAssertEqual(facts.tripDays, 2)
        XCTAssertEqual(facts.mostTimesBought, 2)
        XCTAssertEqual(facts.mappedTrips, 0)
        XCTAssertTrue(facts.mapsStore)
        XCTAssertTrue(facts.isShared)
        XCTAssertEqual(facts.tried, ["drag"])

        let done = service.milestones(for: store, mapsStore: false, isShared: false, tried: [])
            .filter(\.isDone).map(\.id)
        XCTAssertEqual(done, ["walk", "nextTrip", "rhythm"])
    }
}
#endif
