import CoreData
import Foundation
import Observation
import ShoppingCore
import ShoppingStore

/// Launch arguments. `-demo` runs on an in-memory store filled with a sample Costco list (for screenshots and
/// previews); `-demoScreen <name>` opens one screen: home (with home-checklist and home-levels scrolled to Coming
/// up), list (default), list-az (the list A to Z), add, trip, edit, zone (the zone map), zones, floorplan,
/// everything, map (the Map tab, during a trip), restock, you, stores (the store chooser), tour, guide, milestones,
/// or milestones-levels.
enum Launch {
    static let arguments = ProcessInfo.processInfo.arguments
    static var isDemo: Bool { arguments.contains("-demo") }
    static var demoScreen: String {
        guard let i = arguments.firstIndex(of: "-demoScreen"), arguments.indices.contains(i + 1) else { return "list" }
        return arguments[i + 1]
    }
    /// The tab a demo screen is on or over.
    static var demoTab: AppTab {
        switch demoScreen {
        case "home", "home-checklist", "home-levels", "stores", "tour", "guide": return .home
        case "map": return .map
        case "restock": return .restock
        case "you", "milestones", "milestones-levels": return .you
        default: return .list
        }
    }
}

/// Who is using this phone. The id is made once and kept; the name is what the other person sees on a shared list.
@Observable
final class Profile {
    @ObservationIgnored private let defaults: UserDefaults
    let id: String
    var name: String {
        didSet { defaults.set(name, forKey: "shopperName") }
    }
    /// Map the store from trips by dead reckoning (issue #5). Experimental, so off until turned on.
    var mapsStore: Bool {
        didSet { defaults.set(mapsStore, forKey: "mapsStore") }
    }
    /// Whether the tour has been seen (or skipped): it opens by itself until then.
    var hasSeenTour: Bool {
        didSet { defaults.set(hasSeenTour, forKey: "hasSeenTour") }
    }

    /// How the List tab groups the list: a stop per zone, or one A to Z card.
    var listGrouping: ListGrouping {
        didSet { defaults.set(listGrouping.rawValue, forKey: "listGrouping") }
    }
    /// How the home screen shows milestones (issue #23).
    var milestoneStyle: MilestoneStyle {
        didSet { defaults.set(milestoneStyle.rawValue, forKey: "milestoneStyle") }
    }
    /// The try-it milestones done on this phone (`Milestones.Try`).
    private(set) var tried: Set<String> {
        didSet { defaults.set(Array(tried).sorted(), forKey: "triedFeatures") }
    }
    /// The milestones already announced, as "store id/milestone id", so each is announced once.
    private(set) var seenMilestones: Set<String> {
        didSet { defaults.set(Array(seenMilestones).sorted(), forKey: "seenMilestones") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let id = defaults.string(forKey: "shopperID") {
            self.id = id
        } else {
            let id = UUID().uuidString
            defaults.set(id, forKey: "shopperID")
            self.id = id
        }
        name = defaults.string(forKey: "shopperName") ?? ""
        mapsStore = defaults.bool(forKey: "mapsStore")
        hasSeenTour = defaults.bool(forKey: "hasSeenTour")
        listGrouping = defaults.string(forKey: "listGrouping").flatMap(ListGrouping.init(rawValue:)) ?? .zone
        milestoneStyle = defaults.string(forKey: "milestoneStyle").flatMap(MilestoneStyle.init(rawValue:)) ?? .checklist
        tried = Set(defaults.stringArray(forKey: "triedFeatures") ?? [])
        seenMilestones = Set(defaults.stringArray(forKey: "seenMilestones") ?? [])
    }

    /// Marks a try-it milestone done (`Milestones.Try`): call it where the feature is used.
    func markTried(_ id: String) {
        if !tried.contains(id) { tried.insert(id) }
    }

    /// Whether `milestone` of `store` has been announced.
    func hasSeen(_ milestone: Milestone, of store: Store) -> Bool {
        seenMilestones.contains(Self.seenKey(milestone, store))
    }

    /// Marks milestones of `store` as announced.
    func markSeen(_ milestones: [Milestone], of store: Store) {
        let keys = milestones.map { Self.seenKey($0, store) }
        if !Set(keys).isSubset(of: seenMilestones) { seenMilestones.formUnion(keys) }
    }

    /// Forgets which milestones were announced (the demo, so every screenshot run starts the same).
    func forgetSeenMilestones() {
        seenMilestones = []
    }

    private static func seenKey(_ milestone: Milestone, _ store: Store) -> String {
        "\(store.id?.uuidString ?? "")/\(milestone.id)"
    }

    var shopper: Shopper { Shopper(id: id, name: name.isEmpty ? "Me" : name) }
}

/// How the List tab groups the list.
enum ListGrouping: String, CaseIterable {
    /// A stop per zone in walking order, on the rail, with walk numbers.
    case zone
    /// Everything on one card, A to Z, each row saying its zone.
    case alphabetical
}

/// How the home screen shows milestones: two takes on issue #23, to choose between on the You tab.
enum MilestoneStyle: String, CaseIterable {
    /// A "Coming up" tray: the next few, each with how far along it is.
    case checklist
    /// A rank that rises as milestones are done, and how far to the next.
    case levels
}

enum AppData {
    /// The iCloud container lists sync through. Xcode creates it the first time the app is signed with the iCloud
    /// capability (Signing & Capabilities → iCloud → CloudKit).
    static let cloudKitContainer = "iCloud.com.jsonify.buckfifty"

    /// The app's store: private and shared stores in Application Support mirrored to iCloud, or in memory with sample
    /// data for `-demo`.
    static func makePersistence(shopper: Shopper) -> Persistence {
        if Launch.isDemo, let demo = try? Persistence(.inMemory) {
            DemoData.fill(demo.viewContext, shopper: shopper, screen: Launch.demoScreen)
            return demo
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BuckFifty", isDirectory: true)
        do {
            let persistence = try Persistence(.cloudKit(containerIdentifier: cloudKitContainer, directory: directory))
            #if DEBUG
            // Run once with -initializeCloudKitSchema (signed in to iCloud) to create the record types in the
            // development environment, then deploy the schema to production in the CloudKit console.
            if Launch.arguments.contains("-initializeCloudKitSchema"),
               let cloudKit = persistence.container as? NSPersistentCloudKitContainer {
                do { try cloudKit.initializeCloudKitSchema(options: []) } catch {
                    print("Buck Fifty: initializeCloudKitSchema failed: \(error)")
                }
            }
            #endif
            return persistence
        } catch {
            // A store that won't open shouldn't stop the app; nothing is kept until it does.
            print("Buck Fifty: couldn't open the store (\(error)); running in memory.")
            guard let fallback = try? Persistence(.inMemory) else { fatalError("Couldn't make an in-memory store") }
            return fallback
        }
    }
}

/// Fetch requests the views use. Built by entity name, as the model is defined in code.
enum Fetch {
    static func stores() -> NSFetchRequest<Store> {
        let request = NSFetchRequest<Store>(entityName: "Store")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }

    static func entries(in store: Store? = nil) -> NSFetchRequest<ListEntry> {
        let request = NSFetchRequest<ListEntry>(entityName: "ListEntry")
        if let store { request.predicate = NSPredicate(format: "item.store == %@", store) }
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }

    static func zones(in store: Store) -> NSFetchRequest<Zone> {
        let request = NSFetchRequest<Zone>(entityName: "Zone")
        request.predicate = NSPredicate(format: "store == %@", store)
        request.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: true),
                                   NSSortDescriptor(key: "name", ascending: true)]
        return request
    }

    static func items(in store: Store) -> NSFetchRequest<Item> {
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.predicate = NSPredicate(format: "store == %@", store)
        request.sortDescriptors = [NSSortDescriptor(key: "normalizedName", ascending: true)]
        return request
    }

    /// Every trip at every store, newest first (the home screen's rhythm and stats).
    static func trips() -> NSFetchRequest<Trip> {
        let request = NSFetchRequest<Trip>(entityName: "Trip")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return request
    }

    static func openTrips(in store: Store) -> NSFetchRequest<Trip> {
        let request = NSFetchRequest<Trip>(entityName: "Trip")
        request.predicate = NSPredicate(format: "store == %@ AND endedAt == nil", store)
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return request
    }
}

/// The sample list for `-demo`.
enum DemoData {
    static func fill(_ context: NSManagedObjectContext, shopper: Shopper, screen: String) {
        let service = ListService(context: context)
        let partner = Shopper(id: "demo-partner", name: "Partner")
        let costco = service.createStore(named: "Costco", zoneNames: DefaultZones.costcoAuroraVillage)
        let zones = costco.sortedZones
        func add(_ name: String, zone: String?, by who: Shopper = shopper, quantity: Int64 = 1, note: String? = nil) {
            guard let entry = service.addToList(name, store: costco, by: who) else { return }
            entry.quantity = quantity
            entry.note = note
            if let zone, let item = entry.item, let match = zones.first(where: { $0.displayName == zone }) {
                service.setZone(match, for: item)
            }
        }
        // Six weekly trips, so the list is in the order they were walked and Restock knows how often each thing is
        // bought: milk, eggs and bananas every week, paper towels every other week, olive oil once a month. The
        // coffee has moved over by the bakery, and its learned place beats its zone's.
        let walked = ["AA batteries", "Bananas", "Paper towels", "Toilet paper", "Sparkling water", "Dish soap",
                      "Olive oil", "Peanut butter", "Chicken thighs", "Eggs", "Greek yogurt", "Milk", "Butter",
                      "Frozen berries", "Coffee beans", "Croissants", "Rotisserie chicken"]
        // Which of the six trips (0 is six weeks ago, 5 last week) bought each thing.
        let bought: [String: Set<Int>] = [
            "AA batteries": [2], "Bananas": [0, 1, 2, 3, 4, 5], "Paper towels": [1, 3, 5], "Toilet paper": [0, 3],
            "Sparkling water": [0, 1, 2, 3, 4, 5], "Dish soap": [0, 3], "Olive oil": [1, 5], "Peanut butter": [0, 4],
            "Chicken thighs": [1, 3, 5], "Eggs": [0, 1, 2, 3, 4, 5], "Greek yogurt": [1, 3, 5],
            "Milk": [0, 1, 2, 3, 4, 5], "Butter": [0, 2, 4], "Frozen berries": [1, 3, 5], "Coffee beans": [0, 2, 4],
            "Croissants": [1, 3, 5], "Rotisserie chicken": [0, 1, 2, 3, 4, 5],
        ]
        // The trips were mapped (issue #5): where each thing was grabbed, in metres from the door, a little apart
        // each time, and the walk through them to the checkout.
        let spots: [String: FloorPoint] = [
            "AA batteries": FloorPoint(x: 6, y: 10), "Bananas": FloorPoint(x: 20, y: 12),
            "Paper towels": FloorPoint(x: 52, y: 8), "Toilet paper": FloorPoint(x: 58, y: 10),
            "Sparkling water": FloorPoint(x: 62, y: 18), "Dish soap": FloorPoint(x: 64, y: 28),
            "Olive oil": FloorPoint(x: 50, y: 36), "Peanut butter": FloorPoint(x: 58, y: 42),
            "Chicken thighs": FloorPoint(x: 68, y: 74), "Eggs": FloorPoint(x: 44, y: 86),
            "Greek yogurt": FloorPoint(x: 36, y: 86), "Milk": FloorPoint(x: 28, y: 86),
            "Butter": FloorPoint(x: 22, y: 86), "Frozen berries": FloorPoint(x: 14, y: 74),
            "Coffee beans": FloorPoint(x: 12, y: 56), "Croissants": FloorPoint(x: 6, y: 48),
            "Rotisserie chicken": FloorPoint(x: 6, y: 26),
        ]
        // Where in each trip (by its number) the advent calendar was found.
        let adventPlaces: [Int: Double] = [2: 0.15, 3: 0.8, 4: 0.4, 5: 0.65]
        costco.gridHeading = 0
        for (tripNumber, weeksAgo) in [6.0, 5, 4, 3, 2, 1].enumerated() {
            let start = Date().addingTimeInterval(-weeksAgo * 7 * 24 * 60 * 60)
            var walk = [FloorPoint.entrance]
            var basket = walked.filter { bought[$0]?.contains(tripNumber) == true }
            // The advent calendar turns up somewhere new every trip (issue #8): it's under Look for it.
            if let place = adventPlaces[tripNumber] {
                basket.insert("Advent calendar", at: min(Int(place * Double(basket.count)), basket.count))
            }
            for (offset, name) in basket.enumerated() {
                guard let entry = service.addToList(name, store: costco, by: shopper, now: start),
                      let checkOff = service.setChecked(entry, true, by: shopper,
                                                        now: start.addingTimeInterval(Double(offset) * 90))
                else { continue }
                let wobble = Double(offset * 7 + tripNumber * 13)
                let point = (spots[name] ?? walk.last ?? .entrance) + FloorPoint(x: 2 * sin(wobble), y: 2 * cos(wobble * 1.3))
                service.setPoint(point, of: checkOff)
                walk.append(point)
            }
            walk.append(FloorPoint(x: 2, y: 16))
            if let trip = service.currentTrip(at: costco, for: shopper, now: start) {
                trip.path = FloorPlan.encode(walk)
            }
            service.finishTrip(at: costco, for: shopper, now: start.addingTimeInterval(Double(basket.count) * 90))
        }
        // Remembered from those trips but not on the list now: Restock says they're running low.
        let restockZones = ["Bananas": "Produce", "Sparkling water": "Beverages, soda & Gatorade",
                            "Dish soap": "Laundry, cleaning & pet", "Butter": "Dairy & center coolers"]
        for (name, zone) in restockZones {
            if let item = service.item(named: name, in: costco), let match = zones.first(where: { $0.displayName == zone }) {
                service.setZone(match, for: item)
            }
        }
        add("AA batteries", zone: "Electronics & optical")
        add("Paper towels", zone: "Paper goods & water")
        add("Toilet paper", zone: "Paper goods & water", by: partner)
        add("Olive oil", zone: "Pantry")
        add("Coffee beans", zone: "Pantry", by: partner, note: "The dark roast")
        add("Peanut butter", zone: "Pantry")
        add("Chicken thighs", zone: "Meat")
        add("Eggs", zone: "Dairy & center coolers", quantity: 2)
        add("Greek yogurt", zone: "Dairy & center coolers", by: partner)
        add("Milk", zone: "Dairy & center coolers")
        add("Frozen berries", zone: "Frozen")
        add("Croissants", zone: "Bakery", note: "If they're fresh")
        add("Rotisserie chicken", zone: "Rotisserie & deli")
        add("Kirkland pesto", zone: nil, by: partner)
        add("Advent calendar", zone: "Home & auto", by: partner)
        // What the on-device model would guess for an item it has never seen (issue #4).
        if let pesto = costco.entries.first(where: { $0.displayName == "Kirkland pesto" })?.item {
            service.applyZoneGuess("Dairy & center coolers", to: pesto)
        }
        // Remembered from earlier trips but not on the list now: they show up as suggestions.
        for name in ["Chicken nuggets", "Chickpeas"] {
            if let entry = service.addToList(name, store: costco, by: shopper) { service.remove(entry) }
        }

        let tjs = service.createStore(named: "Trader Joe's")
        for name in ["Bananas", "Dark chocolate"] { service.addToList(name, store: tjs, by: shopper) }

        if screen == "trip" || screen == "map" {
            // You and your partner shopping the same list at once: two trips.
            let start = Date().addingTimeInterval(-14 * 60)
            for (offset, name) in ["AA batteries", "Paper towels", "Olive oil"].enumerated() {
                if let entry = costco.entries.first(where: { $0.displayName == name }) {
                    service.setChecked(entry, true, by: shopper, now: start.addingTimeInterval(Double(offset) * 240))
                }
            }
            if let entry = costco.entries.first(where: { $0.displayName == "Greek yogurt" }) {
                service.setChecked(entry, true, by: partner, now: start.addingTimeInterval(500))
            }
        }
        try? service.save()
    }
}
