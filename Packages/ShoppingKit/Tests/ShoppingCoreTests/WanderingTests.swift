import XCTest
@testable import ShoppingCore

final class WanderingTests: XCTestCase {
    let wandering = Wandering()

    func testSpreadOutPositionsOverThreeTripsWander() {
        XCTAssertTrue(wandering.isWandering([0.1, 0.8, 0.4], wasWandering: false))
        XCTAssertTrue(wandering.isWandering([0.1, 0.75, 0.4, 0.9, 0.3], wasWandering: false))
    }

    func testFewerThanThreeTripsNeverWander() {
        XCTAssertFalse(wandering.isWandering([], wasWandering: false))
        XCTAssertFalse(wandering.isWandering([0.05, 0.95], wasWandering: false))
    }

    func testAConsistentItemDoesNotWander() {
        XCTAssertFalse(wandering.isWandering([0.4, 0.45, 0.5, 0.42, 0.48], wasWandering: false))
        // Spread just under the threshold.
        XCTAssertFalse(wandering.isWandering([0.3, 0.5, 0.7], wasWandering: false))
        XCTAssertEqual(LearnedPosition.spread(of: [0.3, 0.5, 0.7]) ?? 1, 0.163, accuracy: 0.001)
    }

    /// One odd trip, or an item that moved across the store, is not wandering.
    func testOneOddTripOrAMoveDoesNotWander() {
        XCTAssertFalse(wandering.isWandering([0.2, 0.2, 0.2, 0.2, 0.8], wasWandering: false))
        XCTAssertFalse(wandering.isWandering([0.2, 0.2, 0.2, 0.8, 0.8], wasWandering: false))
        XCTAssertFalse(wandering.isWandering([0.2, 0.2, 0.8, 0.8], wasWandering: false))
        XCTAssertFalse(wandering.isWandering([0.2, 0.2, 0.8], wasWandering: false))
    }

    /// Only the last five positions count: old history doesn't keep an item flagged or unflagged.
    func testOnlyTheLatestWindowCounts() {
        let settledLongAgo = [0.5, 0.5, 0.5, 0.5, 0.5]
        XCTAssertTrue(wandering.isWandering(settledLongAgo + [0.1, 0.9, 0.3, 0.7, 0.5], wasWandering: false))
        XCTAssertFalse(wandering.isWandering([0.1, 0.9, 0.3, 0.7, 0.5] + settledLongAgo, wasWandering: false))
    }

    /// Once flagged it stays flagged until three trips in a row agree.
    func testAWanderingItemNeedsThreeConsistentTripsToSettle() {
        var recent = [0.1, 0.8, 0.4]
        XCTAssertTrue(wandering.isWandering(recent, wasWandering: false))
        recent.append(0.6)
        XCTAssertTrue(wandering.isWandering(recent, wasWandering: true))
        recent.append(0.62)
        XCTAssertTrue(wandering.isWandering(recent, wasWandering: true), "Two consistent trips aren't enough")
        recent.append(0.58)
        XCTAssertFalse(wandering.isWandering(recent, wasWandering: true), "Three consistent trips settle it")
        // Three that agree but not within the tolerance don't.
        XCTAssertTrue(wandering.isWandering([0.1, 0.8, 0.4, 0.5, 0.6, 0.7], wasWandering: true))
        // And it's not flagged again straight away.
        XCTAssertFalse(wandering.isWandering(recent, wasWandering: false))
    }

    func testLargestCluster() {
        XCTAssertEqual(Wandering.largestCluster([], within: 0.15), 0)
        XCTAssertEqual(Wandering.largestCluster([0.9, 0.1, 0.2, 0.25, 0.6], within: 0.15), 3)
        XCTAssertEqual(Wandering.largestCluster([0.1, 0.5, 0.9], within: 0.15), 1)
    }

    func testOverridesBeatTheTrips() {
        XCTAssertTrue(Wandering.effective(learned: true, override: nil))
        XCTAssertFalse(Wandering.effective(learned: false, override: nil))
        XCTAssertTrue(Wandering.effective(learned: false, override: .wanders))
        XCTAssertFalse(Wandering.effective(learned: true, override: .fixed))
        XCTAssertEqual(WanderOverride(rawValue: "wanders"), .wanders)
        XCTAssertNil(WanderOverride(rawValue: "sometimes"))
    }

    func testNoteSaysWhereItHasBeenSeen() {
        XCTAssertEqual(wandering.note([0.2, 0.75, 0.4]), "Seen anywhere from 20% to 75% of the way in, last at 40%")
        XCTAssertEqual(wandering.note([0.5, 0.51]), "Seen 50% of the way in")
        XCTAssertNil(wandering.note([0.5]))
        XCTAssertNil(wandering.note([]))
        // The window: a long-ago 0.0 is forgotten.
        XCTAssertEqual(wandering.note([0, 0.3, 0.6, 0.4, 0.5, 0.35]),
                       "Seen anywhere from 30% to 60% of the way in, last at 35%")
    }

    func testWanderingEntriesGoFirstUnderLookForIt() {
        let entries = [
            Entry(sortName: "Rotisserie chicken", zoneIndex: 2, learnedPosition: 0.9),
            Entry(sortName: "Pumpkin pie", zoneIndex: 2, learnedPosition: 0.95, isWandering: true),
            Entry(sortName: "Bananas", zoneIndex: 0, learnedPosition: 0.1),
            Entry(sortName: "Advent calendar", zoneIndex: 1, learnedPosition: 0.5, isWandering: true),
            Entry(sortName: "Hot cocoa", zoneIndex: 1, isChecked: true, isWandering: true),
        ]
        XCTAssertEqual(ListOrdering.sorted(entries).map(\.sortName),
                       ["Advent calendar", "Pumpkin pie", "Bananas", "Rotisserie chicken", "Hot cocoa"])
        let sections = ListOrdering.sections(entries, zoneNames: ["Front", "Middle", "Back"])
        XCTAssertEqual(sections.map(\.kind), [.lookForIt, .zone(0), .zone(2), .inCart])
        XCTAssertEqual(sections.first?.title, ListOrdering.lookForItTitle)
        XCTAssertEqual(sections.first?.entries.map(\.sortName), ["Advent calendar", "Pumpkin pie"])
        // At home too, one Look for it section.
        let home = ListOrdering.sections(entries, zoneNames: ["Front", "Middle", "Back"], oneSectionPerZone: true)
        XCTAssertEqual(home.map(\.kind), [.lookForIt, .zone(0), .zone(2), .inCart])
    }
}
