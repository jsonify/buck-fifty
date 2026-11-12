#if canImport(CoreData)
import CoreData
import XCTest
import ShoppingCore
@testable import ShoppingStore

final class HomeListingTests: XCTestCase {
    var persistence: Persistence!
    var service: ListService!
    let jason = Shopper(id: "jason-id", name: "Jason")
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        persistence = try Persistence(.inMemory)
        service = ListService(context: persistence.viewContext, policy: TripPolicy(quietPeriod: 45 * 60))
    }

    func testTheListAtHomeIsInTheOrderYouTypedAndDragged() throws {
        let store = service.createStore(named: "Costco", now: t0)
        for (offset, name) in ["Milk", "Eggs", "Bread", "Coffee"].enumerated() {
            service.addToList(name, store: store, by: jason, now: t0.addingTimeInterval(Double(offset)))
        }
        try service.save()
        XCTAssertEqual(service.homeList(in: store).map(\.displayName), ["Milk", "Eggs", "Bread", "Coffee"])

        service.moveAtHome(service.homeList(in: store), from: 3, to: 0)
        try service.save()
        XCTAssertEqual(service.homeList(in: store).map(\.displayName), ["Coffee", "Milk", "Eggs", "Bread"])

        // Something new goes at the bottom.
        service.addToList("Butter", store: store, by: jason, now: t0.addingTimeInterval(10))
        XCTAssertEqual(service.homeList(in: store).last?.displayName, "Butter")
    }

    func testPastItemsCountPurchasesAndTheLastTrip() throws {
        let store = service.createStore(named: "Costco", now: t0)
        for (trip, names) in [["Milk", "Eggs"], ["Milk"]].enumerated() {
            let start = t0.addingTimeInterval(Double(trip) * 7 * 86_400)
            for name in names {
                if let entry = service.addToList(name, store: store, by: jason, now: start) {
                    service.setChecked(entry, true, by: jason, now: start)
                }
            }
            service.finishTrip(at: store, for: jason, now: start.addingTimeInterval(60))
        }
        service.addToList("Chickpeas", store: store, by: jason, now: t0.addingTimeInterval(20 * 86_400))
        try service.save()

        let past = service.pastItems(in: store, now: t0.addingTimeInterval(21 * 86_400))
        let byName = Dictionary(uniqueKeysWithValues: past.map { ($0.name, $0) })
        XCTAssertEqual(byName["Milk"]?.timesBought, 2)
        XCTAssertEqual(byName["Eggs"]?.timesBought, 1)
        XCTAssertEqual(byName["Milk"]?.boughtLastTrip, true)
        XCTAssertEqual(byName["Eggs"]?.boughtLastTrip, false)
        XCTAssertEqual(byName["Chickpeas"]?.isOnList, true)
        XCTAssertEqual(PastItems.filtered(past, by: .usual).map(\.name), ["Milk", "Eggs"])
    }

    func testWhatATripDidntGetCanBeDropped() throws {
        let store = service.createStore(named: "Costco", now: t0)
        let milk = try XCTUnwrap(service.addToList("Milk", store: store, by: jason, now: t0))
        service.addToList("Sourdough", store: store, by: jason, now: t0)
        service.setChecked(milk, true, by: jason, now: t0)
        service.finishTrip(at: store, for: jason, now: t0.addingTimeInterval(60))
        try service.save()

        XCTAssertEqual(service.leftovers(in: store).map(\.displayName), ["Sourdough"])
        XCTAssertEqual(service.dropLeftovers(in: store), 1)
        try service.save()
        XCTAssertTrue(store.entries.isEmpty)
        // Still remembered, for Past items.
        XCTAssertNotNil(service.item(named: "Sourdough", in: store))
    }
}
#endif
