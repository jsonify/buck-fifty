import Foundation

// Milestones (issue #23): what Buck Fifty has learned about a store, what it learns next and how soon, and the
// features worth trying, so nothing that only switches on after a few trips goes unnoticed.
//
// Two kinds. Earned ones come from shopping: their progress is worked out from the store's own data (trips,
// purchases, mapped walks), so they're the same on every phone that shares the list. Try-it ones are features you
// find by using them once; whether you have is kept on the phone. The targets are the thresholds the features
// themselves use (RouteLearning, Restock, Wandering, FloorPlan), so a milestone is done exactly when its feature works.

/// What a store's data, and this phone, say about the features: the facts milestones are worked out from.
public struct MilestoneFacts: Equatable, Sendable {
    /// Finished trips with at least two check-offs: the ones that teach the walk.
    public var teachingTrips: Int
    /// The days the store was shopped on.
    public var tripDays: Int
    /// The most days any one thing was bought on.
    public var mostTimesBought: Int
    /// Trips with a mapped walk.
    public var mappedTrips: Int
    /// Things whose zone is a guess by Apple Intelligence, not yet kept or fixed.
    public var guessedZones: Int
    /// Whether Map the store is on, on this phone.
    public var mapsStore: Bool
    /// Whether the store's list is shared.
    public var isShared: Bool
    /// The try-it milestones (by id) done on this phone.
    public var tried: Set<String>

    public init(teachingTrips: Int = 0, tripDays: Int = 0, mostTimesBought: Int = 0, mappedTrips: Int = 0,
                guessedZones: Int = 0, mapsStore: Bool = false, isShared: Bool = false, tried: Set<String> = []) {
        self.teachingTrips = teachingTrips
        self.tripDays = tripDays
        self.mostTimesBought = mostTimesBought
        self.mappedTrips = mappedTrips
        self.guessedZones = guessedZones
        self.mapsStore = mapsStore
        self.isShared = isShared
        self.tried = tried
    }
}

/// One feature, and how far along it is.
public struct Milestone: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Switches on by itself after enough shopping.
        case earned
        /// There all along; done the first time you use it.
        case tryIt
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let systemImage: String
    /// What it does for you, once it's on.
    public let does: String
    /// How to get there: what it's waiting for, or how to try it.
    public let howTo: String
    /// The guide part that explains it (`GuidePart.id` in the app).
    public let guidePart: String
    public let progress: Int
    public let target: Int
    /// The unit `progress` counts ("trip", "day"), singular; nil for a try-it.
    public let unit: String?
    /// Something that has to happen before progress can start (Map the store off, say), or nil.
    public let blockedBy: String?

    public init(id: String, kind: Kind, title: String, systemImage: String, does: String, howTo: String,
                guidePart: String, progress: Int, target: Int, unit: String? = nil, blockedBy: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.systemImage = systemImage
        self.does = does
        self.howTo = howTo
        self.guidePart = guidePart
        self.progress = min(max(progress, 0), target)
        self.target = max(target, 1)
        self.unit = unit
        self.blockedBy = blockedBy
    }

    public var isDone: Bool { progress >= target }
    /// How many more (trips, days…) until it's done.
    public var remaining: Int { target - progress }
    /// 0…1.
    public var fraction: Double { Double(progress) / Double(target) }

    /// Progress in words: "Done", "2 of 3 trips", "1 more day", "Try it", or what it's waiting for.
    public var status: String {
        if isDone { return "Done" }
        if let blockedBy { return blockedBy }
        guard let unit else { return "Try it" }
        return "\(progress) of \(target) \(Milestones.plural(unit, target))"
    }

    /// When it comes, in words: "After 1 more trip", "After 2 more days". Nil once done, for a try-it or when blocked.
    public var eta: String? {
        guard !isDone, blockedBy == nil, let unit else { return nil }
        return "After \(remaining) more \(Milestones.plural(unit, remaining))"
    }
}

/// A rank, from how many milestones are done (the Levels style).
public struct MilestoneLevel: Equatable, Sendable {
    /// 1 to `Milestones.levelTitles.count`.
    public let number: Int
    public let title: String
    /// Milestones done.
    public let done: Int
    /// Milestones done to reach the next level, or nil at the top.
    public let nextAt: Int?
    /// The next level's title, or nil at the top.
    public let nextTitle: String?

    /// How many more milestones to the next level, or nil at the top.
    public var toNext: Int? { nextAt.map { $0 - done } }
}

public enum Milestones {
    /// The ids of the try-it milestones, for marking them where the feature is used.
    public enum Try {
        public static let restock = "restock"
        public static let everything = "everything"
        public static let drag = "drag"
        public static let spot = "spot"
        public static let layout = "layout"
        public static let share = "share"
        public static let map = "map"
        /// Not a try-it: kept with them so a guess, once confirmed (and no longer marked guessed), still counts.
        public static let guess = "guess"
    }

    /// Every milestone for one store: earned ones first in the order they usually come, then the ones to try.
    public static func all(_ facts: MilestoneFacts) -> [Milestone] {
        let wanderTrips = Wandering().minimumTrips
        let mapTrips = FloorPlan.recentPoints
        return [
            Milestone(id: "walk", kind: .earned, title: "Learns your walk", systemImage: "figure.walk",
                      does: "The list goes in the order you walk the store, not just by zone.",
                      howTo: "Check off two or more things on a trip, then tap Done.",
                      guidePart: "learning", progress: facts.teachingTrips, target: 1, unit: "trip"),
            Milestone(id: "nextTrip", kind: .earned, title: "Knows when you'll go", systemImage: "calendar",
                      does: "The week strip marks the day of your next trip, from how often you go.",
                      howTo: "Shop the store on two different days.",
                      guidePart: "home", progress: facts.tripDays, target: 2, unit: "day"),
            Milestone(id: "rhythm", kind: .earned, title: "Knows what's running low", systemImage: "clock.arrow.circlepath",
                      does: "Restock says what will run out before your next trip, and home lists it.",
                      howTo: "Buy the same thing on two different days.",
                      guidePart: "restock", progress: facts.mostTimesBought, target: 2, unit: "purchase"),
            Milestone(id: "staples", kind: .earned, title: "Spots your staples", systemImage: "star",
                      does: "Restock picks out what you buy on half your trips or more.",
                      howTo: "Shop the store on three different days.",
                      guidePart: "restock", progress: facts.tripDays, target: 3, unit: "day"),
            Milestone(id: "lookForIt", kind: .earned, title: "Look for it", systemImage: "binoculars",
                      does: "Things that turn up all over the store (seasonal, treasure-hunt finds) go to the top "
                        + "of the list, with where they've been seen.",
                      howTo: "Keep checking things off as you grab them: it watches \(wanderTrips) trips.",
                      guidePart: "learning", progress: facts.teachingTrips, target: wanderTrips, unit: "trip"),
            Milestone(id: "floorPlan", kind: .earned, title: "A floor plan", systemImage: "map",
                      does: "The map key shows where everything is, coloured by zone, with your last walk.",
                      howTo: facts.mapsStore
                        ? "Tap Start trip at the door and keep the app open while you shop."
                        : "Turn on Map the store on the You tab, then tap Start trip at the door.",
                      guidePart: "map", progress: facts.mappedTrips, target: mapTrips, unit: "mapped trip",
                      blockedBy: facts.mapsStore || facts.mappedTrips > 0 ? nil : "Map the store is off"),
            Milestone(id: "guess", kind: .earned, title: "Guesses zones", systemImage: "sparkles",
                      does: "Something new gets its zone guessed on the iPhone, from your zones and what's in them.",
                      howTo: "Add something the store has never seen. Needs Apple Intelligence.",
                      guidePart: "zones", progress: facts.guessedZones > 0 || facts.tried.contains(Try.guess) ? 1 : 0,
                      target: 1),
            tryIt(Try.restock, facts, title: "Open Restock", systemImage: "checklist",
                  does: "Everything the store remembers, with what you'll run out of first.",
                  howTo: "Tap Restock under a list's keys, or the Restock key at home.", guidePart: "restock"),
            tryIt(Try.drag, facts, title: "Drag an item into place", systemImage: "hand.draw",
                  does: "Teach the walk yourself: the list remembers where you put it.",
                  howTo: "Hold an item on the list and drag it onto another.", guidePart: "list"),
            tryIt(Try.everything, facts, title: "Look over a trip", systemImage: "tray.full",
                  does: "Your last trip in the order you grabbed things, and everything the store remembers.",
                  howTo: "Tap Everything on the List tab at home.", guidePart: "everything"),
            tryIt(Try.spot, facts, title: "Set an item's spot", systemImage: "mappin.and.ellipse",
                  does: "Say yourself whether something moves around or has a fixed spot.",
                  howTo: "Hold an item, then pick Moves around or Fixed spot under Spot.", guidePart: "learning"),
            tryIt(Try.layout, facts, title: "Start from a layout", systemImage: "square.stack.3d.up",
                  does: "Zones for a typical Costco, or the Aurora Village floor plan, in one go.",
                  howTo: "Tap Zones on a list, then a layout under Start from a layout.", guidePart: "zones"),
            tryIt(Try.share, facts, title: "Share the list", systemImage: "person.2", done: facts.isShared,
                  does: "Someone else sees every change within seconds, and their trips teach the order too.",
                  howTo: "Tap the share key on a list and send the invitation.", guidePart: "sharing"),
            tryIt(Try.map, facts, title: "Map the store", systemImage: "location.north.line", done: facts.mapsStore,
                  does: "Experimental: your steps and the compass trace your walk into a floor plan.",
                  howTo: "Turn on Map the store on the You tab.", guidePart: "map"),
        ]
    }

    private static func tryIt(_ id: String, _ facts: MilestoneFacts, title: String, systemImage: String,
                              done: Bool = false, does: String, howTo: String, guidePart: String) -> Milestone {
        Milestone(id: id, kind: .tryIt, title: title, systemImage: systemImage, does: does, howTo: howTo,
                  guidePart: guidePart, progress: done || facts.tried.contains(id) ? 1 : 0, target: 1)
    }

    /// What's coming: the earned ones not done yet, nearest first (fewest to go, then as listed; blocked ones last),
    /// then the try-its not done yet.
    public static func upNext(_ milestones: [Milestone]) -> [Milestone] {
        let earned = milestones.enumerated().filter { $0.element.kind == .earned && !$0.element.isDone }
            .sorted { a, b in
                let (x, y) = (a.element, b.element)
                if (x.blockedBy == nil) != (y.blockedBy == nil) { return x.blockedBy == nil }
                if x.remaining != y.remaining { return x.remaining < y.remaining }
                return a.offset < b.offset
            }
            .map(\.element)
        return earned + milestones.filter { $0.kind == .tryIt && !$0.isDone }
    }

    /// The ones done that aren't in `seen` (ids), as listed: what to announce.
    public static func newlyDone(_ milestones: [Milestone], seen: Set<String>) -> [Milestone] {
        milestones.filter { $0.isDone && !seen.contains($0.id) }
    }

    /// The level titles, lowest first.
    public static let levelTitles = ["New in town", "Regular", "Knows the aisles", "Seasoned", "Knows the store"]

    /// The level for `done` milestones of `total`: the titles spread evenly, the top one only with every one done.
    public static func level(done: Int, of total: Int) -> MilestoneLevel {
        let count = levelTitles.count
        let total = max(total, 1)
        let done = min(max(done, 0), total)
        // Level n (0-based) starts at n/(count-1) of the way, rounded up; the last needs them all.
        let starts = (0..<count).map { n in n == count - 1 ? total : Int((Double(total * n) / Double(count - 1)).rounded(.up)) }
        let index = starts.lastIndex { $0 <= done } ?? 0
        let next = index + 1 < count ? index + 1 : nil
        return MilestoneLevel(number: index + 1, title: levelTitles[index], done: done,
                              nextAt: next.map { starts[$0] }, nextTitle: next.map { levelTitles[$0] })
    }

    /// "trip" or "trips", by count.
    public static func plural(_ unit: String, _ count: Int) -> String { count == 1 ? unit : unit + "s" }
}
