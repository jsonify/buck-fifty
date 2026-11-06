import CoreData
import Foundation
import Observation
import ShoppingCore
import ShoppingStore

/// Launch arguments. `-demo` runs on an in-memory store filled with a sample Costco list (for screenshots and
/// previews); `-demoScreen <name>` opens one screen: stores, list (default), add, trip, edit, zones, map or everything.
enum Launch {
    static let arguments = ProcessInfo.processInfo.arguments
    static var isDemo: Bool { arguments.contains("-demo") }
    static var demoScreen: String {
        guard let i = arguments.firstIndex(of: "-demoScreen"), arguments.indices.contains(i + 1) else { return "list" }
        return arguments[i + 1]
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
    }

    var shopper: Shopper { Shopper(id: id, name: name.isEmpty ? "Me" : name) }
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
        let costco = service.createStore(named: "Costco")
        let zones = costco.sortedZones
        func add(_ name: String, zone: Int?, by who: Shopper = shopper, quantity: Int64 = 1, note: String? = nil) {
            guard let entry = service.addToList(name, store: costco, by: who) else { return }
            entry.quantity = quantity
            entry.note = note
            if let zone, zones.indices.contains(zone), let item = entry.item { service.setZone(zones[zone], for: item) }
        }
        // Two earlier trips, so the list is in the order they were walked. The coffee has moved over by the bakery,
        // and its learned place beats its zone's.
        let walked = ["AA batteries", "Paper towels", "Toilet paper", "Olive oil", "Peanut butter", "Chicken thighs",
                      "Eggs", "Greek yogurt", "Milk", "Frozen berries", "Coffee beans", "Croissants",
                      "Rotisserie chicken"]
        // Both trips were mapped (issue #5): where each thing was grabbed, in metres from the door, a little apart
        // each time, and the walk through them to the checkout.
        let spots: [String: FloorPoint] = [
            "AA batteries": FloorPoint(x: 6, y: 10), "Paper towels": FloorPoint(x: 52, y: 8),
            "Toilet paper": FloorPoint(x: 58, y: 10), "Olive oil": FloorPoint(x: 50, y: 36),
            "Peanut butter": FloorPoint(x: 58, y: 42), "Chicken thighs": FloorPoint(x: 68, y: 74),
            "Eggs": FloorPoint(x: 44, y: 86), "Greek yogurt": FloorPoint(x: 36, y: 86),
            "Milk": FloorPoint(x: 28, y: 86), "Frozen berries": FloorPoint(x: 14, y: 74),
            "Coffee beans": FloorPoint(x: 12, y: 56), "Croissants": FloorPoint(x: 6, y: 48),
            "Rotisserie chicken": FloorPoint(x: 6, y: 26),
        ]
        costco.gridHeading = 0
        for (tripNumber, daysAgo) in [14.0, 7.0].enumerated() {
            let start = Date().addingTimeInterval(-daysAgo * 24 * 60 * 60)
            var walk = [FloorPoint.entrance]
            for (offset, name) in walked.enumerated() {
                guard let entry = service.addToList(name, store: costco, by: shopper, now: start),
                      let checkOff = service.setChecked(entry, true, by: shopper,
                                                        now: start.addingTimeInterval(Double(offset) * 90))
                else { continue }
                let wobble = Double(offset * 7 + tripNumber * 13)
                let point = (spots[name] ?? .entrance) + FloorPoint(x: 2 * sin(wobble), y: 2 * cos(wobble * 1.3))
                service.setPoint(point, of: checkOff)
                walk.append(point)
            }
            walk.append(FloorPoint(x: 2, y: 16))
            if let trip = service.currentTrip(at: costco, for: shopper, now: start) {
                trip.path = FloorPlan.encode(walk)
            }
            service.finishTrip(at: costco, for: shopper, now: start.addingTimeInterval(Double(walked.count) * 90))
        }
        add("AA batteries", zone: 0)
        add("Paper towels", zone: 2)
        add("Toilet paper", zone: 2, by: partner)
        add("Olive oil", zone: 3)
        add("Coffee beans", zone: 3, by: partner, note: "The dark roast")
        add("Peanut butter", zone: 3)
        add("Chicken thighs", zone: 4)
        add("Eggs", zone: 5, quantity: 2)
        add("Greek yogurt", zone: 5, by: partner)
        add("Milk", zone: 5)
        add("Frozen berries", zone: 6)
        add("Croissants", zone: 7, note: "If they're fresh")
        add("Rotisserie chicken", zone: 8)
        add("Kirkland pesto", zone: nil, by: partner)
        // What the on-device model would guess for an item it has never seen (issue #4).
        if let pesto = costco.entries.first(where: { $0.displayName == "Kirkland pesto" })?.item {
            service.applyZoneGuess("Back cooler wall", to: pesto)
        }
        // Remembered from earlier trips but not on the list now: they show up as suggestions.
        for name in ["Chicken nuggets", "Chickpeas"] {
            if let entry = service.addToList(name, store: costco, by: shopper) { service.remove(entry) }
        }

        let tjs = service.createStore(named: "Trader Joe's")
        for name in ["Bananas", "Dark chocolate"] { service.addToList(name, store: tjs, by: shopper) }

        if screen == "trip" {
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
