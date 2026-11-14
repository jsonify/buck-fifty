import XCTest
@testable import ShoppingCore

final class RestockTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// Noon on a Monday (2023-11-13), so a few hours either way stays on the same day.
    let monday = Date(timeIntervalSince1970: 1_699_876_800)
    let day: TimeInterval = 24 * 60 * 60

    func daysAgo(_ n: Double) -> Date { monday.addingTimeInterval(-n * day) }

    func testDaysAreDistinctAndSorted() {
        let days = Restock.days([daysAgo(1), daysAgo(7), daysAgo(1).addingTimeInterval(3600)], calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertLessThan(days[0], days[1])
    }

    func testMedianGap() {
        let days = Restock.days([daysAgo(21), daysAgo(14), daysAgo(7), daysAgo(0)], calendar: calendar)
        XCTAssertEqual(Restock.medianGap(days), 7 * day)
        XCTAssertNil(Restock.medianGap(Array(days.prefix(1))))
        // An odd week out doesn't move the median.
        let uneven = Restock.days([daysAgo(30), daysAgo(14), daysAgo(7), daysAgo(0)], calendar: calendar)
        XCTAssertEqual(Restock.medianGap(uneven), 7 * day)
    }

    func testRhythmPredictsTheNextTrip() {
        let rhythm = ShoppingRhythm(tripDates: [daysAgo(21), daysAgo(14), daysAgo(7)], calendar: calendar)
        XCTAssertEqual(rhythm.tripDays, 3)
        XCTAssertEqual(rhythm.interval, 7 * day)
        XCTAssertEqual(rhythm.nextTrip, calendar.startOfDay(for: monday))
        XCTAssertNil(ShoppingRhythm(tripDates: [daysAgo(3)], calendar: calendar).nextTrip)
    }

    func testEstimateCountsTripsSinceTheFirstPurchase() {
        let trips = [daysAgo(35), daysAgo(28), daysAgo(21), daysAgo(14), daysAgo(7)]
        let estimate = Restock.estimate(bought: [daysAgo(28), daysAgo(14)], trips: trips, calendar: calendar)
        XCTAssertEqual(estimate.timesBought, 2)
        XCTAssertEqual(estimate.interval, 14 * day)
        XCTAssertEqual(estimate.tripsSinceFirst, 4)
        XCTAssertEqual(estimate.tripShare, 0.5, accuracy: 0.001)
        XCTAssertTrue(estimate.isStaple)
        XCTAssertEqual(estimate.dueDate, calendar.startOfDay(for: daysAgo(0)))
    }

    func testNeverOrOnceBoughtHasNoRhythm() {
        XCTAssertEqual(Restock.estimate(bought: [], trips: [daysAgo(1)], calendar: calendar).timesBought, 0)
        let once = Restock.estimate(bought: [daysAgo(3)], trips: [daysAgo(10), daysAgo(3)], calendar: calendar)
        XCTAssertNil(once.interval)
        XCTAssertFalse(once.isStaple)
        XCTAssertEqual(Restock.urgency(of: once, now: monday, rhythm: ShoppingRhythm(tripDates: [])), .unknown)
    }

    func testUrgencyLooksAheadToTheNextTrip() {
        // Weekly trips, the last one 2 days ago: the next is in 5 days.
        let rhythm = ShoppingRhythm(tripDates: [daysAgo(16), daysAgo(9), daysAgo(2)], calendar: calendar)
        func urgency(every interval: Double, lastBought: Double) -> RestockUrgency {
            let last = calendar.startOfDay(for: daysAgo(lastBought))
            let estimate = RestockEstimate(timesBought: 3, lastBought: last, interval: interval * day)
            return Restock.urgency(of: estimate, now: monday, rhythm: rhythm)
        }
        // Weekly milk bought on the last trip runs out before the next one.
        XCTAssertEqual(urgency(every: 7, lastBought: 2), .due)
        // Fortnightly paper towels bought on the last trip: due the trip after next.
        XCTAssertEqual(urgency(every: 14, lastBought: 2), .soon)
        // Monthly olive oil bought on the last trip can wait.
        XCTAssertEqual(urgency(every: 30, lastBought: 2), .later)
        // Weekly coffee last bought three weeks ago is well past due.
        XCTAssertEqual(urgency(every: 7, lastBought: 21), .overdue)
        XCTAssertTrue(RestockUrgency.overdue.isNeeded)
        XCTAssertFalse(RestockUrgency.soon.isNeeded)
    }

    func testShelves() {
        XCTAssertEqual(Restock.shelf(urgency: .overdue, isStaple: false), .needed)
        XCTAssertEqual(Restock.shelf(urgency: .soon, isStaple: true), .soon)
        XCTAssertEqual(Restock.shelf(urgency: .later, isStaple: true), .staples)
        XCTAssertEqual(Restock.shelf(urgency: .unknown, isStaple: false), .rest)
        XCTAssertEqual(Restock.shelf(urgency: .overdue, isStaple: true, muted: true), .rest)
    }

    func testSkipLastsUntilTheNextTripStarts() {
        let skippedAt = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(Restock.isSkipped(skippedAt: nil, latestTrip: skippedAt))
        XCTAssertTrue(Restock.isSkipped(skippedAt: skippedAt, latestTrip: nil))
        XCTAssertTrue(Restock.isSkipped(skippedAt: skippedAt, latestTrip: skippedAt.addingTimeInterval(-60)))
        XCTAssertFalse(Restock.isSkipped(skippedAt: skippedAt, latestTrip: skippedAt.addingTimeInterval(60)))
    }

    func testWords() {
        XCTAssertEqual(Restock.describe(interval: 7 * day), "Every week")
        XCTAssertEqual(Restock.describe(interval: 9 * day), "Every 9 days")
        XCTAssertEqual(Restock.describe(interval: 14 * day), "Every 2 weeks")
        XCTAssertEqual(Restock.describe(interval: 30 * day), "Every month")
        XCTAssertNil(Restock.describe(interval: nil))
        XCTAssertEqual(Restock.ago(daysAgo(0), now: monday, calendar: calendar), "today")
        XCTAssertEqual(Restock.ago(daysAgo(1), now: monday, calendar: calendar), "yesterday")
        XCTAssertEqual(Restock.ago(daysAgo(9), now: monday, calendar: calendar), "9 days ago")
        XCTAssertEqual(Restock.until(monday.addingTimeInterval(2 * day), now: monday, calendar: calendar), "in 2 days")
        XCTAssertEqual(Restock.until(daysAgo(3), now: monday, calendar: calendar), "today")
        XCTAssertEqual(Restock.chip(.overdue), "LATE")
        XCTAssertEqual(Restock.chip(.later), "")
    }
}
