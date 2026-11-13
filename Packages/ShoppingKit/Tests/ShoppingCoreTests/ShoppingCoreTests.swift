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

    func testAuroraVillageLayout() {
        let zones = DefaultZones.costcoAuroraVillage
        XCTAssertEqual(zones.count, 21)
        XCTAssertEqual(zones.first, "Electronics & optical")
        XCTAssertEqual(Array(zones.suffix(3)), ["Checkout", "Food court", "Pharmacy lockers"])
        XCTAssertEqual(Set(zones.map(ItemName.normalized)).count, zones.count, "No two zones share a name")
        XCTAssertEqual(DefaultZones.zones(forStoreNamed: "Costco Aurora Village"), zones)
        XCTAssertEqual(DefaultZones.zones(forStoreNamed: "Costco"), DefaultZones.costco)
        XCTAssertTrue(DefaultZones.layouts[0].matches(zones.map { $0.uppercased() }))
        XCTAssertFalse(DefaultZones.layouts[0].matches(DefaultZones.costco))
    }
}

struct Entry: ListSortable, Equatable {
    var sortName: String
    var zoneIndex: Int?
    var isChecked = false
    var learnedPosition: Double?
    var isWandering = false
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

final class LearnedOrderTests: XCTestCase {
    func testLearnedPositionsBeatZonesAndZoneAveragesStandInForTheRest() {
        let entries = [
            Entry(sortName: "Coffee", zoneIndex: 1, learnedPosition: 0.9),   // moved to the back
            Entry(sortName: "Tea", zoneIndex: 1),                            // its zone, not learned yet
            Entry(sortName: "Steak", zoneIndex: 2, learnedPosition: 0.5),
            Entry(sortName: "TV", zoneIndex: 0, learnedPosition: 0.05),
            Entry(sortName: "Batteries", zoneIndex: nil, learnedPosition: 0.1),
            Entry(sortName: "Pesto", zoneIndex: nil),
        ]
        // The store's Pantry items average 0.3 (Coffee's old place among them), so Tea, not learned yet, goes there.
        let sections = ListOrdering.sections(entries, zoneNames: ["Front", "Pantry", "Meat"], zonePositions: [1: 0.3])
        XCTAssertEqual(sections.flatMap(\.entries).map(\.sortName),
                       ["TV", "Batteries", "Tea", "Steak", "Coffee", "Pesto"])
        XCTAssertEqual(sections.map(\.kind), [.zone(0), .unzoned, .zone(1), .zone(2), .zone(1), .unzoned])
        XCTAssertEqual(Set(sections.map(\.id)).count, sections.count, "Section ids are unique")
        XCTAssertEqual(sections.map(\.title).last, ListOrdering.unzonedTitle)
    }

    func testOneSectionPerZoneAtHome() {
        let entries = [
            Entry(sortName: "Coffee", zoneIndex: 1, learnedPosition: 0.9),
            Entry(sortName: "Tea", zoneIndex: 1),
            Entry(sortName: "Steak", zoneIndex: 2, learnedPosition: 0.5),
            Entry(sortName: "TV", zoneIndex: 0, learnedPosition: 0.05),
            Entry(sortName: "Batteries", zoneIndex: nil, learnedPosition: 0.1),
            Entry(sortName: "Pesto", zoneIndex: nil),
        ]
        // The same list as above, but Coffee joins Tea under Pantry and Pesto joins Batteries, each in walk order.
        let sections = ListOrdering.sections(entries, zoneNames: ["Front", "Pantry", "Meat"], zonePositions: [1: 0.3],
                                             oneSectionPerZone: true)
        XCTAssertEqual(sections.map(\.kind), [.zone(0), .unzoned, .zone(1), .zone(2)])
        XCTAssertEqual(sections.map { $0.entries.map(\.sortName) },
                       [["TV"], ["Batteries", "Pesto"], ["Tea", "Coffee"], ["Steak"]])
        XCTAssertEqual(Set(sections.map(\.id)).count, sections.count)
    }

    func testAlphabeticalIgnoresZonesAndCheckOffs() {
        let entries = [
            Entry(sortName: "steak", zoneIndex: 2, learnedPosition: 0.5),
            Entry(sortName: "Coffee", zoneIndex: 1, isChecked: true),
            Entry(sortName: "Bananas", zoneIndex: 0),
            Entry(sortName: "Écorce", zoneIndex: nil),
        ]
        XCTAssertEqual(ListOrdering.alphabetical(entries).map(\.sortName), ["Bananas", "Coffee", "Écorce", "steak"])
    }

    func testZoneAverages() {
        let averages = ListOrdering.zoneAverages([(zone: 0, position: 0.2), (zone: 0, position: 0.4),
                                                  (zone: 1, position: nil), (zone: nil, position: 0.9)])
        XCTAssertEqual(averages.count, 1)
        XCTAssertEqual(averages[0] ?? -1, 0.3, accuracy: 1e-9)
    }
}

final class ZonePlanTests: XCTestCase {
    let plan = PlanDrawing(aspect: 2, blocks: [
        PlanBlock("Frozen", zone: "Frozen", x: 0, y: 0, width: 0.5, height: 0.5),
        PlanBlock("Strip", zone: "Snacks", x: 0.5, y: 0, width: 0.5, height: 0.02),
        PlanBlock("Restrooms", zone: nil, x: 0.5, y: 0.5, width: 0.5, height: 0.5),
    ], entranceX: 1, entranceY: 1)

    func testTappingABlockChoosesItsZone() {
        // A 200 x 100 drawing.
        XCTAssertEqual(plan.block(atX: 50, y: 25, width: 200, height: 100)?.zone, "Frozen")
        XCTAssertEqual(plan.block(atX: 150, y: 1, width: 200, height: 100)?.zone, "Snacks")
        XCTAssertEqual(plan.block(atX: 150, y: 12, width: 200, height: 100)?.zone, "Snacks",
                       "A thin strip is easy to hit")
        XCTAssertNil(plan.block(atX: 190, y: 90, width: 200, height: 100, tolerance: 5),
                     "Places that aren't zones aren't chosen")
    }

    func testTurningUpright() {
        let upright = plan.upright
        XCTAssertEqual(upright.aspect, 0.5)
        XCTAssertEqual(upright.blocks[0].rect, PlanRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(upright.blocks[1].rect.width, 0.02, accuracy: 1e-9)
        XCTAssertEqual(upright.blocks[1].rect.height, 0.5, accuracy: 1e-9)
        XCTAssertEqual(upright.blocks[1].rect.x, 0.98, accuracy: 1e-9)
        XCTAssertEqual(upright.entranceX, 0)
        XCTAssertEqual(upright.entranceY, 1)
        XCTAssertEqual(upright.exit, upright.entrance, "The exit is the entrance unless set")
    }

    func testDoorsSetOnTheMap() {
        let moved = plan.withDoors(entrance: PlanPoint(x: 0, y: 1), exit: PlanPoint(x: 0.5, y: 1))
        XCTAssertEqual(moved.entrance, PlanPoint(x: 0, y: 1))
        XCTAssertEqual(moved.exit, PlanPoint(x: 0.5, y: 1))
        XCTAssertEqual(plan.withDoors(entrance: nil, exit: nil), plan)
        XCTAssertEqual(moved.upright.exit, moved.exit.upright)
        // A tap on the upright drawing lands back where it was on the plan.
        let point = PlanPoint(x: 0.3, y: 0.8)
        let tapped = point.upright
        XCTAssertEqual(PlanPoint.fromUpright(x: tapped.x, y: tapped.y).x, point.x, accuracy: 1e-9)
        XCTAssertEqual(PlanPoint.fromUpright(x: tapped.x, y: tapped.y).y, point.y, accuracy: 1e-9)
        XCTAssertEqual(PlanPoint(x: -1, y: 2).clamped, PlanPoint(x: 0, y: 1))
    }

    func testWalkingOrderFollowsTheDoors() {
        // Four zones along the front, A at the left to D at the right, and one the drawing doesn't show.
        let row = PlanDrawing(aspect: 4, blocks: ["A", "B", "C", "D"].enumerated().map { index, name in
            PlanBlock(name, zone: name, x: 0.05 + Double(index) * 0.25, y: 0.4, width: 0.15, height: 0.2)
        }, entranceX: 0, entranceY: 0.5)
        let names = ["C", "Food court", "A", "D", "B"]
        XCTAssertEqual(row.walkingOrder(of: names), ["A", "B", "C", "Food court", "D"],
                       "Nearest first from the door; the food court stays after the C it followed")
        let fromTheRight = row.withDoors(entrance: PlanPoint(x: 1, y: 0.5), exit: PlanPoint(x: 1, y: 0.5))
        XCTAssertEqual(fromTheRight.walkingOrder(of: ["A", "B", "C", "D"]).first, "D")
        // In at the left and out at the right: left to right, not back again.
        let through = row.withDoors(entrance: PlanPoint(x: 0, y: 0.5), exit: PlanPoint(x: 1, y: 0.5))
        XCTAssertEqual(through.walkingOrder(of: ["D", "B", "A", "C"]), ["A", "B", "C", "D"])
        XCTAssertEqual(row.walkingOrder(of: ["Food court"]), ["Food court"])
    }

    func testTheAuroraVillagePlanCoversEveryZone() {
        let aurora = DefaultZones.costcoAuroraVillagePlan
        XCTAssertEqual(aurora.zones, Set(DefaultZones.costcoAuroraVillage))
        for block in aurora.blocks {
            XCTAssertTrue((0...1.001).contains(block.rect.x + block.rect.width), block.label)
            XCTAssertTrue((0...1.001).contains(block.rect.y + block.rect.height), block.label)
        }
        XCTAssertEqual(DefaultZones.plan(forZones: DefaultZones.costcoAuroraVillage), aurora)
        XCTAssertNil(DefaultZones.plan(forZones: DefaultZones.costco))
        XCTAssertNil(DefaultZones.plan(forZones: []))
    }
}

final class DragMoveTests: XCTestCase {
    /// The indices of `keys` in list order once the move from `from` to `to` has written its positions.
    func order(_ keys: [Double?], from: Int, to: Int) -> [Int] {
        var keys = keys
        for (index, position) in ListOrdering.positionsAfterMove(keys, from: from, to: to) { keys[index] = position }
        return keys.indices.sorted { (keys[$0] ?? .infinity, $0) < (keys[$1] ?? .infinity, $1) }
    }

    func testMovedEntryLandsBetweenItsNewNeighbours() {
        let keys: [Double?] = [0.1, 0.3, 0.5, 0.7]
        XCTAssertEqual(ListOrdering.positionsAfterMove(keys, from: 0, to: 2), [0: 0.6])
        XCTAssertEqual(order(keys, from: 0, to: 2), [1, 2, 0, 3])
        XCTAssertEqual(order(keys, from: 3, to: 0), [3, 0, 1, 2])
        XCTAssertEqual(order(keys, from: 1, to: 3), [0, 2, 3, 1])
    }

    func testMovingIntoATieSpreadsTheTie() {
        // Three items placed only by their zone share a position; drop the last item between two of them.
        let keys: [Double?] = [0.2, 0.5, 0.5, 0.5, 0.8]
        XCTAssertEqual(order(keys, from: 4, to: 2), [0, 1, 4, 2, 3])
        XCTAssertEqual(order(keys, from: 1, to: 3), [0, 2, 3, 1, 4])
    }

    func testMovingAmongEntriesWithoutPositions() {
        let keys: [Double?] = [0.2, 0.6, nil, nil, nil]
        XCTAssertEqual(order(keys, from: 0, to: 3), [1, 2, 3, 0, 4])
        XCTAssertEqual(order([0.2, 0.6, nil], from: 0, to: 1), [1, 0, 2])
        XCTAssertEqual(order(keys, from: 4, to: 0), [4, 0, 1, 2, 3])
    }

    func testNoMove() {
        XCTAssertTrue(ListOrdering.positionsAfterMove([0.1, 0.2], from: 1, to: 1).isEmpty)
        XCTAssertTrue(ListOrdering.positionsAfterMove([0.1, 0.2], from: 0, to: 5).isEmpty)
    }
}

final class ZoneGuessTests: XCTestCase {
    func testPromptListsZonesInOrderWithExamples() {
        let prompt = ZoneGuess.prompt(item: " kirkland  pesto ", store: "Costco", zones: [
            ZoneExamples(name: "Pantry aisles", items: ["Olive oil", "Coffee", "Peanut butter", "Rice", "Flour"]),
            ZoneExamples(name: "Back cooler wall", items: ["Milk"]),
            ZoneExamples(name: "Bakery"),
        ])
        XCTAssertEqual(prompt, """
            Store: Costco
            Zones, in walking order:
            - Pantry aisles: Olive oil, Coffee, Peanut butter, Rice
            - Back cooler wall: Milk
            - Bakery
            Item: kirkland pesto
            Which zone is it in?
            """)
    }

    func testOnlyARealZoneCounts() {
        let zones = ["Pantry aisles", "Back cooler wall"]
        XCTAssertEqual(ZoneGuess.resolve("  back cooler WALL", zoneNames: zones), 1)
        XCTAssertNil(ZoneGuess.resolve("Garden centre", zoneNames: zones))
        XCTAssertNil(ZoneGuess.resolve("", zoneNames: zones))
        XCTAssertNil(ZoneGuess.resolve(nil, zoneNames: zones))
    }
}

final class DeadReckoningTests: XCTestCase {
    func assertPoint(_ p: FloorPoint?, _ x: Double, _ y: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p?.x ?? .nan, x, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(p?.y ?? .nan, y, accuracy: 1e-6, file: file, line: line)
    }

    func testWalkingTracesFromTheDoor() {
        var reckoning = DeadReckoning()
        assertPoint(reckoning.walk(10, heading: 90), 10, 0)    // east
        assertPoint(reckoning.walk(5, heading: 0), 10, 5)      // north
        assertPoint(reckoning.walk(0, heading: 180), 10, 5)
    }

    func testHeadingsSnapToTheAislesGrid() {
        let reckoning = DeadReckoning(gridHeading: 30)
        XCTAssertEqual(reckoning.walkingHeading(40), 30, accuracy: 1e-9)
        XCTAssertEqual(reckoning.walkingHeading(125), 120, accuracy: 1e-9)
        XCTAssertEqual(reckoning.walkingHeading(285), 300, accuracy: 1e-9)
        XCTAssertEqual(reckoning.walkingHeading(75), 75, accuracy: 1e-9, "Halfway between aisles stays as it is")
        XCTAssertEqual(DeadReckoning(gridHeading: 350).walkingHeading(10), 350, accuracy: 1e-9)
        XCTAssertEqual(DeadReckoning().walkingHeading(-90), 270, accuracy: 1e-9)
    }

    func testMeanHeadingWrapsAroundNorth() {
        let mean = DeadReckoning.meanHeading([350, 10]) ?? .nan
        XCTAssertEqual(abs(DeadReckoning.signedDifference(mean, 0)), 0, accuracy: 1e-6)
        XCTAssertEqual(DeadReckoning.meanHeading([80, 100]) ?? .nan, 90, accuracy: 1e-6)
        XCTAssertNil(DeadReckoning.meanHeading([]))
    }

    func testDriftIsSpreadBackBetweenKnownPoints() {
        let path = (0...4).map { FloorPoint(x: Double($0), y: 0) }
        // Ended 2 m north of where it thought: the checkout is a known point.
        let atCheckout = PathCorrection.corrected(path, anchors: [4: FloorPoint(x: 4, y: 2)])
        XCTAssertEqual(atCheckout.map(\.y), [0, 0.5, 1, 1.5, 2])
        XCTAssertEqual(atCheckout.map(\.x), [0, 1, 2, 3, 4])
        // A landmark halfway: after it the correction holds.
        let landmark = PathCorrection.corrected(path, anchors: [2: FloorPoint(x: 2, y: 1)])
        XCTAssertEqual(landmark.map(\.y), [0, 0.5, 1, 1, 1])
        XCTAssertEqual(PathCorrection.currentOffset(path, anchors: [2: FloorPoint(x: 2, y: 1)]), FloorPoint(x: 0, y: 1))
        XCTAssertEqual(PathCorrection.currentOffset(path, anchors: [:]), FloorPoint(x: 0, y: 0))
        XCTAssertEqual(PathCorrection.corrected(path, anchors: [:]), path)
    }

    func testTurningToTheGrid() {
        let east = FloorPoint(x: 1, y: 0).rotated(toHeading: 90)
        assertPoint(east, 0, 1)
    }
}

final class FloorPlanTests: XCTestCase {
    func testMedianIsRobust() {
        XCTAssertEqual(FloorPlan.median([FloorPoint(x: 0, y: 0), FloorPoint(x: 10, y: 10), FloorPoint(x: 1, y: 1)]),
                       FloorPoint(x: 1, y: 1))
        XCTAssertEqual(FloorPlan.median([FloorPoint(x: 0, y: 0), FloorPoint(x: 2, y: 4)]), FloorPoint(x: 1, y: 2))
        XCTAssertNil(FloorPlan.median([]))
    }

    func testOnlyASettledSpotIsALandmark() {
        XCTAssertEqual(FloorPlan.landmark([FloorPoint(x: 0, y: 0), FloorPoint(x: 1, y: 0), FloorPoint(x: 0, y: 1)]),
                       FloorPoint(x: 0, y: 0))
        XCTAssertNil(FloorPlan.landmark([FloorPoint(x: 0, y: 0), FloorPoint(x: 20, y: 0), FloorPoint(x: 0, y: 20)]))
        XCTAssertNil(FloorPlan.landmark([FloorPoint(x: 0, y: 0), FloorPoint(x: 0, y: 0)]), "Too few points yet")
    }

    func testThinningKeepsTheEnds() {
        let path = [0, 0.5, 1, 2, 2.2].map { FloorPoint(x: $0, y: 0) }
        XCTAssertEqual(FloorPlan.thinned(path).map(\.x), [0, 2, 2.2])
        XCTAssertEqual(FloorPlan.thinned([FloorPoint.entrance]), [FloorPoint.entrance])
        XCTAssertEqual(FloorPlan.thinned([]), [])
    }

    func testPathRoundTripsAsText() {
        let path = [FloorPoint(x: 1.5, y: 2), FloorPoint(x: 3, y: -4)]
        let text = FloorPlan.encode(path)
        XCTAssertEqual(text, "1.5,2.0;3.0,-4.0")
        XCTAssertEqual(FloorPlan.decode(text), path)
        XCTAssertEqual(FloorPlan.decode("junk;1,2"), [FloorPoint(x: 1, y: 2)])
        XCTAssertNil(FloorPlan.encode([]))
    }
}

final class RouteLearningTests: XCTestCase {
    let learning = RouteLearning()
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// A trip checking off `names` in order, `gap` seconds apart.
    func trip(_ names: [String], gap: TimeInterval = 60) -> [RouteStop<String>] {
        names.enumerated().map { RouteStop(item: $1, time: t0.addingTimeInterval(Double($0) * gap)) }
    }

    func testRankPositions() {
        let p = learning.rankPositions(trip(["a", "b", "c", "d", "e"]))
        XCTAssertEqual(p, ["a": 0, "b": 0.25, "c": 0.5, "d": 0.75, "e": 1])
    }

    func testRankIgnoresLongPausesButTimeDoesNot() {
        // Ten minutes chatting in the bakery between b and c.
        let stops = [RouteStop(item: "a", time: t0), RouteStop(item: "b", time: t0.addingTimeInterval(60)),
                     RouteStop(item: "c", time: t0.addingTimeInterval(660)),
                     RouteStop(item: "d", time: t0.addingTimeInterval(720))]
        XCTAssertEqual(learning.rankPositions(stops)["b"] ?? -1, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(learning.timePositions(stops)["b"] ?? -1, 60.0 / 720, accuracy: 1e-9)
        XCTAssertEqual(learning.timePositions(stops)["d"], 1)
    }

    func testOutOfOrderAndRepeatedStopsCountOnceInTimeOrder() {
        let stops = [RouteStop(item: "b", time: t0.addingTimeInterval(60)), RouteStop(item: "a", time: t0),
                     RouteStop(item: "a", time: t0.addingTimeInterval(120)),
                     RouteStop(item: "c", time: t0.addingTimeInterval(180))]
        XCTAssertEqual(learning.usableStops(stops).map(\.item), ["a", "b", "c"])
    }

    func testOneCheckOffTeachesNothing() {
        XCTAssertTrue(learning.rankPositions(trip(["a"])).isEmpty)
        XCTAssertTrue(learning.timePositions(trip(["a"])).isEmpty)
        XCTAssertTrue(learning.rankPositions([RouteStop<String>]()).isEmpty)
    }

    func testEndOfTripBurstIsIgnored() {
        // Walked a, b, c, then checked the rest off at the checkout under a second apart.
        var stops = trip(["a", "b", "c"])
        let checkout = t0.addingTimeInterval(600)
        for (i, name) in ["x", "y", "z", "w"].enumerated() {
            stops.append(RouteStop(item: name, time: checkout.addingTimeInterval(Double(i) * 0.6)))
        }
        XCTAssertEqual(learning.usableStops(stops).map(\.item), ["a", "b", "c"])
        XCTAssertEqual(learning.rankPositions(stops), ["a": 0, "b": 0.5, "c": 1])
        XCTAssertNil(learning.timePositions(stops)["x"])
    }

    func testTwoQuickCheckOffsAtTheEndStillCount() {
        // Two things off the same shelf a second apart are not a "check all".
        var stops = trip(["a", "b"])
        stops.append(RouteStop(item: "c", time: t0.addingTimeInterval(61)))
        XCTAssertEqual(learning.usableStops(stops).map(\.item), ["a", "b", "c"])
    }

    func testAllInOneBurstTeachesNothing() {
        XCTAssertTrue(learning.rankPositions(trip(["a", "b", "c", "d"], gap: 0.5)).isEmpty)
    }

    func testMovingAverageForgetsAndKeepsRecentSamples() {
        var p = LearnedPosition()
        p = learning.updated(p, with: 0.5)
        XCTAssertEqual(p.position, 0.5)
        p = learning.updated(p, with: 0.6)
        XCTAssertEqual(p.position ?? -1, 0.54, accuracy: 1e-9)
        for _ in 0..<20 { p = learning.updated(p, with: 0.5) }
        XCTAssertEqual(p.sampleCount, 22)
        XCTAssertEqual(p.recent.count, learning.sampleLimit)
        XCTAssertEqual(p.spread ?? -1, 0, accuracy: 1e-9)
        // One odd trip only nudges it.
        p = learning.updated(p, with: 0.9)
        XCTAssertEqual(p.position ?? -1, 0.66, accuracy: 1e-4)
    }

    func testSamplesRoundTripAsText() {
        let text = LearnedPosition.encode([0.25, 0.8, 1])
        XCTAssertEqual(text, "0.250,0.800,1.000")
        XCTAssertEqual(LearnedPosition.decode(text), [0.25, 0.8, 1])
        XCTAssertEqual(LearnedPosition.decode(nil), [])
        XCTAssertNil(LearnedPosition.encode([]))
    }

    /// The coffee is at 20% of the walk for months, then moves to 80%: after at most two trips the list puts it in
    /// its new place.
    func testMovedItemSortsInItsNewPlaceWithinTwoTrips() {
        let before = ["a", "b", "coffee", "c", "d", "e", "f", "g", "h", "i", "j"]
        let after = ["a", "b", "c", "d", "e", "f", "g", "h", "coffee", "i", "j"]
        var learned: [String: LearnedPosition] = [:]
        func walk(_ route: [String]) {
            for (name, p) in learning.rankPositions(trip(route)) {
                learned[name] = learning.updated(learned[name] ?? LearnedPosition(), with: p)
            }
        }
        func listOrder() -> [String] {
            let entries = before.shuffled().map {
                Entry(sortName: $0, zoneIndex: nil, learnedPosition: learned[$0]?.position)
            }
            return ListOrdering.sorted(entries).map(\.sortName)
        }

        for _ in 0..<30 { walk(before) }
        XCTAssertEqual(learned["coffee"]?.position ?? -1, 0.2, accuracy: 1e-6)
        XCTAssertEqual(listOrder(), before)

        walk(after)
        walk(after)
        XCTAssertEqual(learned["coffee"]?.position ?? -1, 0.8, accuracy: 1e-6)
        XCTAssertEqual(listOrder(), after)
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
