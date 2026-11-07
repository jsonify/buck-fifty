import XCTest
@testable import ShoppingCore

final class MilestonesTests: XCTestCase {
    func milestone(_ id: String, _ facts: MilestoneFacts) -> Milestone {
        Milestones.all(facts).first { $0.id == id }!
    }

    func testANewStoreHasNothingDone() {
        let all = Milestones.all(MilestoneFacts())
        XCTAssertFalse(all.contains(where: \.isDone))
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "ids are unique")
        XCTAssertEqual(milestone("walk", MilestoneFacts()).status, "0 of 1 trip")
        XCTAssertEqual(milestone("walk", MilestoneFacts()).eta, "After 1 more trip")
        XCTAssertEqual(milestone("drag", MilestoneFacts()).status, "Try it")
        XCTAssertNil(milestone("drag", MilestoneFacts()).eta)
    }

    func testTargetsMatchTheFeaturesThresholds() {
        XCTAssertEqual(milestone("lookForIt", MilestoneFacts()).target, Wandering().minimumTrips)
        XCTAssertEqual(milestone("floorPlan", MilestoneFacts(mapsStore: true)).target, FloorPlan.recentPoints)
        XCTAssertEqual(milestone("rhythm", MilestoneFacts()).target, 2)
    }

    func testEarnedProgress() {
        let facts = MilestoneFacts(teachingTrips: 2, tripDays: 2, mostTimesBought: 2)
        XCTAssertTrue(milestone("walk", facts).isDone)
        XCTAssertTrue(milestone("nextTrip", facts).isDone)
        XCTAssertTrue(milestone("rhythm", facts).isDone)
        XCTAssertEqual(milestone("staples", facts).status, "2 of 3 days")
        XCTAssertEqual(milestone("lookForIt", facts).eta, "After 1 more trip")
        // Progress never runs past the target.
        XCTAssertEqual(milestone("walk", MilestoneFacts(teachingTrips: 9)).progress, 1)
    }

    func testFloorPlanWaitsForMapTheStore() {
        let off = milestone("floorPlan", MilestoneFacts())
        XCTAssertEqual(off.status, "Map the store is off")
        XCTAssertNil(off.eta)
        XCTAssertEqual(milestone("floorPlan", MilestoneFacts(mappedTrips: 4, mapsStore: true)).status,
                       "4 of 10 mapped trips")
    }

    func testTryItsAreDoneByUseOrByState() {
        XCTAssertTrue(milestone("drag", MilestoneFacts(tried: [Milestones.Try.drag])).isDone)
        XCTAssertTrue(milestone("share", MilestoneFacts(isShared: true)).isDone)
        XCTAssertTrue(milestone("map", MilestoneFacts(mapsStore: true)).isDone)
        XCTAssertTrue(milestone("guess", MilestoneFacts(guessedZones: 1)).isDone)
        XCTAssertTrue(milestone("guess", MilestoneFacts(tried: [Milestones.Try.guess])).isDone)
    }

    func testUpNextPutsTheNearestFirstAndBlockedLast() {
        let facts = MilestoneFacts(teachingTrips: 2, tripDays: 2, mostTimesBought: 1)
        let next = Milestones.upNext(Milestones.all(facts))
        XCTAssertFalse(next.contains(where: \.isDone))
        // One more purchase, day or trip each; then the guess; Map the store is off, so the floor plan is last of
        // the earned ones; then the try-its.
        XCTAssertEqual(next.prefix(3).map(\.id), ["rhythm", "staples", "lookForIt"])
        let earned = next.filter { $0.kind == .earned }
        XCTAssertEqual(earned.last?.id, "floorPlan")
        XCTAssertEqual(next.firstIndex { $0.kind == .tryIt }, earned.count)
    }

    func testNewlyDoneSkipsWhatWasSeen() {
        let all = Milestones.all(MilestoneFacts(teachingTrips: 1, tripDays: 2))
        XCTAssertEqual(Milestones.newlyDone(all, seen: []).map(\.id), ["walk", "nextTrip"])
        XCTAssertEqual(Milestones.newlyDone(all, seen: ["walk"]).map(\.id), ["nextTrip"])
    }

    func testLevels() {
        XCTAssertEqual(Milestones.level(done: 0, of: 14).title, "New in town")
        XCTAssertEqual(Milestones.level(done: 0, of: 14).nextAt, 4)
        XCTAssertEqual(Milestones.level(done: 4, of: 14).title, "Regular")
        XCTAssertEqual(Milestones.level(done: 6, of: 14).toNext, 1)
        XCTAssertEqual(Milestones.level(done: 13, of: 14).title, "Seasoned")
        let top = Milestones.level(done: 14, of: 14)
        XCTAssertEqual(top.title, "Knows the store")
        XCTAssertEqual(top.number, Milestones.levelTitles.count)
        XCTAssertNil(top.nextAt)
        XCTAssertNil(top.nextTitle)
    }
}
