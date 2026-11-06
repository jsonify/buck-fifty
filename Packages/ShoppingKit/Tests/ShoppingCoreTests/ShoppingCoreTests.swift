import XCTest
@testable import ShoppingCore

final class ItemNameTests: XCTestCase {
    func testCleanedCollapsesWhitespaceAndKeepsCase() {
        XCTAssertEqual(ItemName.cleaned("  Kirkland   pesto \n"), "Kirkland pesto")
    }

    func testNormalizedFoldsCaseAndAccents() {
        XCTAssertEqual(ItemName.normalized("  Crème  Fraîche"), "creme fraiche")
        XCTAssertEqual(ItemName.normalized("OLIVE OIL"), ItemName.normalized("olive oil"))
    }
}

final class ItemSuggesterTests: XCTestCase {
    let names = ["Paper towels", "Kirkland paper towels", "Rotisserie chicken", "Chicken thighs", "Peanut butter"]

    func suggest(_ q: String, limit: Int = 5) -> [String] {
        ItemSuggester.suggestions(for: q, in: names, limit: limit) { $0 }
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertEqual(suggest("  "), [])
    }

    func testPrefixBeatsWordPrefixBeatsContains() {
        XCTAssertEqual(suggest("chicken"), ["Chicken thighs", "Rotisserie chicken"])
        XCTAssertEqual(suggest("pa"), ["Paper towels", "Kirkland paper towels"])
        XCTAssertEqual(suggest("towel"), ["Paper towels", "Kirkland paper towels"])
        XCTAssertEqual(suggest("isser"), ["Rotisserie chicken"])
    }

    func testExactMatchComesFirst() {
        XCTAssertEqual(suggest("paper towels").first, "Paper towels")
    }

    func testLimit() {
        XCTAssertEqual(suggest("p", limit: 1), ["Paper towels"])
    }
}

final class DefaultZonesTests: XCTestCase {
    func testCostcoGetsWalkingOrderZones() {
        XCTAssertEqual(DefaultZones.zones(forStoreNamed: "Costco Business Center"), DefaultZones.costco)
        XCTAssertEqual(DefaultZones.costco.first, "Entrance electronics")
        XCTAssertEqual(DefaultZones.costco.last, "Rotisserie corner")
        XCTAssertEqual(DefaultZones.zones(forStoreNamed: "Trader Joe's"), DefaultZones.generic)
    }
}

struct Entry: ListSortable, Equatable {
    var sortName: String
    var zoneIndex: Int?
    var isChecked = false
}

final class ListOrderingTests: XCTestCase {
    func testZonesInWalkingOrderThenUnzonedThenCart() {
        let entries = [
            Entry(sortName: "Rotisserie chicken", zoneIndex: 8),
            Entry(sortName: "Batteries", zoneIndex: nil),
            Entry(sortName: "Eggs", zoneIndex: 5, isChecked: true),
            Entry(sortName: "TV", zoneIndex: 0),
            Entry(sortName: "bananas", zoneIndex: 5),
            Entry(sortName: "Apples", zoneIndex: 5),
        ]
        XCTAssertEqual(ListOrdering.sorted(entries).map(\.sortName),
                       ["TV", "Apples", "bananas", "Rotisserie chicken", "Batteries", "Eggs"])

        let sections = ListOrdering.sections(entries, zoneNames: DefaultZones.costco)
        XCTAssertEqual(sections.map(\.kind), [.zone(0), .zone(5), .zone(8), .unzoned, .inCart])
        XCTAssertEqual(sections.map(\.title),
                       ["Entrance electronics", "Back cooler wall", "Rotisserie corner",
                        ListOrdering.unzonedTitle, ListOrdering.inCartTitle])
        XCTAssertEqual(sections[1].entries.map(\.sortName), ["Apples", "bananas"])
    }

    func testZoneIndexOutOfRangeCountsAsUnzoned() {
        let sections = ListOrdering.sections([Entry(sortName: "Milk", zoneIndex: 42)], zoneNames: ["Dairy"])
        XCTAssertEqual(sections.map(\.kind), [.unzoned])
    }

    func testEmptyListHasNoSections() {
        XCTAssertTrue(ListOrdering.sections([Entry](), zoneNames: ["Dairy"]).isEmpty)
    }
}

final class TripPolicyTests: XCTestCase {
    func testTripLapsesAfterQuietPeriod() {
        let policy = TripPolicy(quietPeriod: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(policy.hasLapsed(lastActivity: start, now: start.addingTimeInterval(59)))
        XCTAssertTrue(policy.hasLapsed(lastActivity: start, now: start.addingTimeInterval(60)))
    }

    func testInitials() {
        XCTAssertEqual(Shopper.initials(of: "Mary Ann Smith"), "MA")
        XCTAssertEqual(Shopper.initials(of: "jason"), "J")
        XCTAssertEqual(Shopper.initials(of: "   "), "?")
    }
}

final class ShareSummaryTests: XCTestCase {
    func testPeople() {
        XCTAssertEqual(ShareSummary(isShared: true).people, "nobody yet")
        XCTAssertEqual(ShareSummary(isShared: true, pending: 1).people, "1 invited")
        XCTAssertEqual(ShareSummary(isShared: true, participants: ["Partner"]).people, "Partner")
        XCTAssertEqual(ShareSummary(isShared: true, participants: ["Partner", "Sam"]).people, "Partner and Sam")
        XCTAssertEqual(ShareSummary(isShared: true, participants: ["A", "B", "C"]).people, "3 people")
        XCTAssertFalse(ShareSummary.notShared.isShared)
    }
}
