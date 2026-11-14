import Foundation

// Restocking: what you're likely to need before the next trip, from what you've bought before.
//
// Every check-off is a purchase with a date, so each item has a rhythm: the typical days between buying it. An item
// bought every week and last bought nine days ago is due; one bought every month and last bought a week ago can wait.
// The store has a rhythm too (the days between trips), which says roughly when the next trip is, so "due" means
// "will run out before the next trip", not "has run out". Purchases and trips are counted by day, so two people
// splitting up in the store, or a second trip on the same day, count once.

/// How often a store is shopped, from the days its trips were on.
public struct ShoppingRhythm: Equatable, Sendable {
    /// The day of the latest trip (start of day), if any.
    public var lastTrip: Date?
    /// The typical time between trips: the median gap between trip days, once there are two.
    public var interval: TimeInterval?
    /// How many days the store was shopped on.
    public var tripDays: Int

    public init(tripDates: [Date], calendar: Calendar = .current) {
        let days = Restock.days(tripDates, calendar: calendar)
        lastTrip = days.last
        interval = Restock.medianGap(days)
        tripDays = days.count
    }

    /// When the next trip probably is: the last trip plus the usual gap. Nil until there have been two trips.
    public var nextTrip: Date? {
        guard let lastTrip, let interval else { return nil }
        return lastTrip.addingTimeInterval(interval)
    }
}

/// How soon an item is needed, most urgent last so they compare by urgency.
public enum RestockUrgency: Int, Comparable, Sendable, CaseIterable {
    /// Bought once, or never: no rhythm yet.
    case unknown
    /// Not due for a while yet.
    case later
    /// Due the trip after next.
    case soon
    /// Will run out before the next trip.
    case due
    /// Should have run out a while ago (half its rhythm or more past due).
    case overdue

    public static func < (a: RestockUrgency, b: RestockUrgency) -> Bool { a.rawValue < b.rawValue }

    /// Whether to put it on the next list.
    public var isNeeded: Bool { self >= .due }
}

/// What an item's purchases say about it.
public struct RestockEstimate: Equatable, Sendable {
    /// How many days it was bought on.
    public var timesBought: Int
    /// The day it was last bought.
    public var lastBought: Date?
    /// The typical time between buying it (median gap between purchase days), once it has been bought twice.
    public var interval: TimeInterval?
    /// Of the store's trip days since the item was first bought, the share it was bought on (0…1).
    public var tripShare: Double
    /// How many of the store's trip days there have been since the first purchase, the days it was bought included.
    public var tripsSinceFirst: Int

    public init(timesBought: Int = 0, lastBought: Date? = nil, interval: TimeInterval? = nil, tripShare: Double = 0,
                tripsSinceFirst: Int = 0) {
        self.timesBought = timesBought
        self.lastBought = lastBought
        self.interval = interval
        self.tripShare = tripShare
        self.tripsSinceFirst = tripsSinceFirst
    }

    /// When it's due again: last bought plus its rhythm.
    public var dueDate: Date? {
        guard let lastBought, let interval else { return nil }
        return lastBought.addingTimeInterval(interval)
    }

    /// A staple: bought on at least half the trips since it was first bought, at least twice, over three trips or
    /// more. Staples are worth a look before every trip even when they aren't due.
    public var isStaple: Bool { timesBought >= 2 && tripShare >= Restock.stapleShare && tripsSinceFirst >= 3 }
}

public enum Restock {
    /// The share of trips an item must be bought on to be a staple.
    public static let stapleShare = 0.5
    static let day: TimeInterval = 24 * 60 * 60

    /// The distinct days among `dates` (each the start of its day), oldest first.
    public static func days(_ dates: [Date], calendar: Calendar = .current) -> [Date] {
        Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted()
    }

    /// The median gap between consecutive `days` (already distinct and sorted), or nil for fewer than two.
    public static func medianGap(_ days: [Date]) -> TimeInterval? {
        guard days.count >= 2 else { return nil }
        let gaps = zip(days.dropFirst(), days).map { $0.timeIntervalSince($1) }.sorted()
        let mid = gaps.count / 2
        return gaps.count % 2 == 1 ? gaps[mid] : (gaps[mid - 1] + gaps[mid]) / 2
    }

    /// What an item's purchase dates say about it, given the dates of the store's trips.
    public static func estimate(bought: [Date], trips: [Date], calendar: Calendar = .current) -> RestockEstimate {
        let boughtDays = days(bought, calendar: calendar)
        guard let first = boughtDays.first else { return RestockEstimate() }
        // The trips since its first purchase include the days it was bought, even if a trip's own date is missing.
        let tripDays = Set(days(trips, calendar: calendar).filter { $0 >= first }).union(boughtDays)
        return RestockEstimate(timesBought: boughtDays.count, lastBought: boughtDays.last,
                               interval: medianGap(boughtDays),
                               tripShare: Double(boughtDays.count) / Double(tripDays.count),
                               tripsSinceFirst: tripDays.count)
    }

    /// How soon the item is needed. "Due" is due by the next trip (or by now, when the next trip is unknown or
    /// already past); "soon" is due within one more trip after that.
    public static func urgency(of estimate: RestockEstimate, now: Date, rhythm: ShoppingRhythm) -> RestockUrgency {
        guard let due = estimate.dueDate, let interval = estimate.interval else { return .unknown }
        if due <= now.addingTimeInterval(-interval / 2) { return .overdue }
        let horizon = max(now, rhythm.nextTrip ?? now)
        if due <= horizon { return .due }
        let tripGap = rhythm.interval ?? interval
        if due <= horizon.addingTimeInterval(tripGap) { return .soon }
        return .later
    }

    /// Whole days from `from` to `to`, by calendar day (negative when `to` is earlier).
    public static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    /// A rhythm in words: "Every day", "Every 9 days", "Every 2 weeks", "Every month", or nil without one.
    public static func describe(interval: TimeInterval?) -> String? {
        guard let interval else { return nil }
        let days = max(Int((interval / day).rounded()), 1)
        switch days {
        case 1: return "Every day"
        case 7: return "Every week"
        case 2...10: return "Every \(days) days"
        case 11...24: return "Every \(Int((Double(days) / 7).rounded())) weeks"
        case 25...45: return "Every month"
        default: return "Every \(Int((Double(days) / 30).rounded())) months"
        }
    }

    /// How long ago, in words: "today", "yesterday", "9 days ago".
    public static func ago(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = daysBetween(date, now, calendar: calendar)
        switch days {
        case ...0: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    /// When, in words, a coming day is: "today", "tomorrow", "in 3 days" (a past day is "today": it's due now).
    public static func until(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = daysBetween(now, date, calendar: calendar)
        switch days {
        case ...0: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }

    /// The short status for an item's chip: "LATE", "DUE", "SOON", or "" when there's nothing to say.
    public static func chip(_ urgency: RestockUrgency) -> String {
        switch urgency {
        case .overdue: return "LATE"
        case .due: return "DUE"
        case .soon: return "SOON"
        case .later, .unknown: return ""
        }
    }

    /// The sections of the restock checklist, in order.
    public enum Shelf: Int, CaseIterable, Sendable, Hashable {
        /// Due (or overdue) before the next trip.
        case needed
        /// Due within a trip after that.
        case soon
        /// Staples that aren't due yet: worth a look every time.
        case staples
        /// Everything else the store remembers.
        case rest

        public var title: String {
            switch self {
            case .needed: return "Before the next trip"
            case .soon: return "Running low soon"
            case .staples: return "Staples"
            case .rest: return "Now and then"
            }
        }
    }

    /// Which section an item goes in. One you've said never to suggest goes with the rest, however due it is.
    public static func shelf(urgency: RestockUrgency, isStaple: Bool, muted: Bool = false) -> Shelf {
        if muted { return .rest }
        switch urgency {
        case .overdue, .due: return .needed
        case .soon: return .soon
        case .later, .unknown: return isStaple ? .staples : .rest
        }
    }

    /// Whether an item skipped for the next trip at `skippedAt` is still skipped: until a trip starts after the skip.
    /// `latestTrip` is when the store's latest trip started.
    public static func isSkipped(skippedAt: Date?, latestTrip: Date?) -> Bool {
        guard let skippedAt else { return false }
        guard let latestTrip else { return true }
        return latestTrip <= skippedAt
    }

    /// Orders an item within its section: the most urgent first, then the most often bought, then by name.
    public static func precedes(_ a: (urgency: RestockUrgency, estimate: RestockEstimate, name: String),
                                _ b: (urgency: RestockUrgency, estimate: RestockEstimate, name: String)) -> Bool {
        if a.urgency != b.urgency { return a.urgency > b.urgency }
        if let da = a.estimate.dueDate, let db = b.estimate.dueDate, da != db { return da < db }
        if a.estimate.tripShare != b.estimate.tripShare { return a.estimate.tripShare > b.estimate.tripShare }
        if a.estimate.timesBought != b.estimate.timesBought { return a.estimate.timesBought > b.estimate.timesBought }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}
