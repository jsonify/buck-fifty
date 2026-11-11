import CoreData
import CoreLocation
import Foundation
import Observation
import ShoppingCore
import ShoppingStore

/// Starts and ends trips by where the phone is (off until turned on, on the You tab). Each store pinned on this phone
/// is a circle the system watches, even with the app closed: coming inside starts a trip when the list has something
/// on it, and going back out ends the trip, so one you forgot to end doesn't run on.
///
/// A store is pinned where you stand when you tap Pin here, or the first time you tap Start trip there with this on.
/// Pins stay on this phone (in its settings, not the shared list): each phone pins the stores it shops at.
@MainActor
@Observable
final class StoreFence {
    static let shared = StoreFence()

    /// The pins, by store id.
    private(set) var pins: [String: StorePin] {
        didSet { UserDefaults.standard.set(StorePin.encode(pins), forKey: "storePins") }
    }
    /// Finding where you are, for a pin.
    private(set) var isLocating = false
    /// Location access, as of the last look (`refresh()`).
    private(set) var authorization: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var listening: Task<Void, Never>?

    /// The monitor's name: the system keeps its circles across launches under it.
    private static let monitorName = "BuckFiftyStores"

    private init() {
        pins = StorePin.decode(UserDefaults.standard.data(forKey: "storePins"))
        authorization = manager.authorizationStatus
    }

    private var profile: Profile { AppModel.shared.profile }

    /// Where `store` is pinned on this phone, if it is.
    func pin(for store: Store) -> StorePin? {
        if Launch.isDemo { return StorePin(latitude: 47.775, longitude: -122.343) }
        guard let id = store.id?.uuidString else { return nil }
        return pins[id]
    }

    /// Picks up watching at launch (in the background too, when a crossing relaunched the app).
    func resume() {
        guard !Launch.isDemo, profile.tripsFollowLocation else { return }
        Task { await watch() }
    }

    /// Turned on or off on the You tab: asks for location access when on, and watches the pinned stores or stops.
    func setOn(_ on: Bool) {
        guard !Launch.isDemo else { return }
        if on { requestAccess() }
        Task { await watch() }
    }

    /// Looks at location access again (when the app comes back from Settings).
    func refresh() {
        authorization = manager.authorizationStatus
    }

    /// Pins `store` where you are now, keeping its radius if it had one.
    func pinHere(_ store: Store) {
        guard !Launch.isDemo, let id = store.id?.uuidString, !isLocating else { return }
        requestAccess()
        isLocating = true
        Task {
            defer { isLocating = false }
            guard let here = await currentLocation() else { return }
            pins[id] = StorePin(latitude: here.coordinate.latitude, longitude: here.coordinate.longitude,
                                radius: pins[id]?.radius ?? StorePin.defaultRadius)
            // You're in the store: don't count pinning it as walking in.
            await watch(inside: id)
        }
    }

    /// Pins `store` where you are, if it isn't pinned yet: Start trip at the store pins it.
    func pinIfNeeded(_ store: Store) {
        guard profile.tripsFollowLocation, pin(for: store) == nil else { return }
        pinHere(store)
    }

    func setRadius(_ radius: Double, for store: Store) {
        guard let id = store.id?.uuidString, pins[id] != nil else { return }
        pins[id]?.radius = radius
        Task { await watch() }
    }

    func forget(_ store: Store) {
        guard let id = store.id?.uuidString else { return }
        pins[id] = nil
        Task { await watch() }
    }

    // MARK: Watching

    private func requestAccess() {
        // From "not asked", this asks for While Using; iOS asks about Always later, the first time a circle is
        // crossed with the app closed. From While Using, it asks about Always once.
        if authorization == .notDetermined || authorization == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        refresh()
    }

    /// Makes the monitor's circles match the pins (none when this is off) and listens for crossings. `inside` is a
    /// store you're in now.
    private func watch(inside: String? = nil) async {
        let monitor = await makeMonitor()
        let wanted = profile.tripsFollowLocation ? pins : [:]
        for id in await monitor.identifiers where wanted[id] == nil {
            await monitor.remove(id)
        }
        for (id, pin) in wanted {
            let center = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
            let record = await monitor.record(for: id)
            if id != inside, let circle = record?.condition as? CLMonitor.CircularGeographicCondition,
               circle.radius == pin.radius, circle.center.latitude == center.latitude,
               circle.center.longitude == center.longitude {
                continue
            }
            // A changed circle keeps the side you were on, so changing the radius isn't a crossing.
            let side: CLMonitor.Event.State = id == inside ? .satisfied : (record?.lastEvent.state ?? .unsatisfied)
            let condition = CLMonitor.CircularGeographicCondition(center: center, radius: pin.radius)
            await monitor.add(condition, identifier: id, assuming: side)
        }
    }

    private func makeMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        let monitor = await CLMonitor(Self.monitorName)
        self.monitor = monitor
        listening = Task {
            do {
                for try await event in await monitor.events {
                    switch event.state {
                    case .satisfied: cross(.arrived, storeID: event.identifier, at: event.date)
                    case .unsatisfied: cross(.left, storeID: event.identifier, at: event.date)
                    default: break
                    }
                }
            } catch {
                print("Buck Fifty: store monitor stopped: \(error)")
            }
        }
        return monitor
    }

    /// Starts or ends your trip at the store whose circle was crossed.
    private func cross(_ crossing: StoreCrossing, storeID: String, at date: Date) {
        guard profile.tripsFollowLocation, let uuid = UUID(uuidString: storeID) else { return }
        let context = AppModel.shared.persistence.viewContext
        let request = NSFetchRequest<Store>(entityName: "Store")
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        guard let store = (try? context.fetch(request))?.first else { return }
        let service = ListService(context: context)
        let trip = service.currentTrip(at: store, for: profile.shopper, now: date)
        let actions = TripActions(store: store, context: context, profile: profile)
        switch LocationTrips.action(for: crossing, hasOpenTrip: trip != nil, itemsLeft: store.remainingCount) {
        case .startTrip:
            // Not mapped: the edge of the car park isn't the door the map starts from.
            actions.start(atDoor: false)
        case .endTrip:
            guard let trip else { return }
            let empty = service.route(of: trip).isEmpty
            _ = actions.finish(trip)
            // Nothing checked off: you drove past, or went in for something else. It isn't a trip to remember.
            if empty {
                context.delete(trip)
                actions.save()
            }
        case .nothing:
            break
        }
    }

    /// Where you are, as soon as it's good to a shop's width, or the best fix within 20 seconds.
    private func currentLocation() async -> CLLocation? {
        let deadline = Date().addingTimeInterval(20)
        var best: CLLocation?
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                refresh()
                if update.authorizationDenied || update.authorizationDeniedGlobally { return nil }
                if let location = update.location, location.horizontalAccuracy >= 0,
                   location.horizontalAccuracy < (best?.horizontalAccuracy ?? .infinity) {
                    best = location
                }
                if let best, best.horizontalAccuracy <= 30 || Date() > deadline { return best }
            }
        } catch {
            print("Buck Fifty: couldn't find where you are: \(error)")
        }
        return best
    }
}
