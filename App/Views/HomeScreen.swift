import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// The Home tab: your most recent store and its list. The add field, then the LCD for the next trip (how much is on
/// the list, what's due, the week on its strip with NEXT on the day the next trip probably is), the list you're
/// building (`HomeListEditor`: Select from inventory, reorder, trash), what's due before the next trip as cards with a
/// red Add, then milestones and the last month. The orange key, Start trip, is for the store: it sorts the list and
/// opens it on the List tab.
struct HomeScreen: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(Profile.self) private var profile
    @Environment(SharingModel.self) private var sharing
    @Environment(Navigator.self) private var navigator
    @FetchRequest private var entries: FetchedResults<ListEntry>
    @FetchRequest private var zones: FetchedResults<Zone>
    @FetchRequest private var items: FetchedResults<Item>
    @FetchRequest private var openTrips: FetchedResults<Trip>
    // Fetched so the week and the last month redraw when any trip changes, here or on the other phone.
    @FetchRequest(fetchRequest: Fetch.trips()) private var trips: FetchedResults<Trip>
    @State private var draft = ""
    @State private var guide: GuideJump?
    @State private var showingMilestones = false

    init(store: Store) {
        self.store = store
        _entries = FetchRequest(fetchRequest: Fetch.entries(in: store))
        _zones = FetchRequest(fetchRequest: Fetch.zones(in: store))
        _items = FetchRequest(fetchRequest: Fetch.items(in: store))
        _openTrips = FetchRequest(fetchRequest: Fetch.openTrips(in: store))
    }

    private var service: ListService { ListService(context: context) }
    private var actions: TripActions { TripActions(store: store, context: context, profile: profile) }
    private var trip: Trip? { service.activeTrip(among: Array(openTrips), for: profile.shopper) }
    private static let comingUpID = "comingUp"

    var body: some View {
        let now = Date()
        let walk = WalkModel(entries: Array(entries), zones: Array(zones), items: Array(items))
        let low = service.neededNotOnList(in: store, now: now)
        let rhythm = service.rhythm(of: store)
        let milestones = MilestoneBoard.milestones(for: store, context: context, profile: profile, sharing: sharing)
        VStack(spacing: 10) {
            ScreenHeader(storeName: store.displayName, title: trip == nil ? "Your list" : "On a trip",
                         chooseStore: { navigator.choosingStore = true }) {
                StorePresencePill(store: store, openTrips: Array(openTrips))
            }
            AddBar(draft: $draft, prompt: "Add to \(store.displayName)…", add: add)
                .padding(.horizontal, 14)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        lcd(walk: walk, due: low.count, rhythm: rhythm, now: now)
                        list(walk)
                        dueCards(low, now: now)
                        newMilestones(milestones)
                        comingUp(milestones).id(Self.comingUpID)
                        lastMonth(now: now)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    // The screenshot demo's -checklist and -levels home screens show Coming up, below the fold otherwise.
                    guard Launch.isDemo, ["home-checklist", "home-levels"].contains(Launch.demoScreen) else { return }
                    DispatchQueue.main.async { proxy.scrollTo(Self.comingUpID, anchor: .center) }
                }
            }
            TripBar(title: trip == nil ? "Start trip · \(walk.left)" : "Back to the trip",
                    systemImage: "cart", action: startTrip) {
                ShareKey(store: store)
            }
        }
        .padding(.top, 4)
        .sheet(item: $guide) { GuideSheet(startAt: $0.id) }
        .sheet(isPresented: $showingMilestones) { MilestonesSheet(store: store) }
        .onAppear {
            guard Launch.isDemo else { return }
            if Launch.demoScreen == "stores" { navigator.choosingStore = true }
        }
    }

    // MARK: The LCD

    private func lcd(walk: WalkModel, due: Int, rhythm: ShoppingRhythm, now: Date) -> TripLCD {
        let others = openTrips.filter { $0.shopperID != profile.id }.compactMap(\.shopperName)
        let label: String
        if trip != nil {
            label = "You're in the store"
        } else if let other = others.first {
            label = "\(other) in the store"
        } else if let next = rhythm.nextTrip {
            label = "At home · next trip \(Restock.until(next, now: now))"
        } else {
            label = "At home"
        }
        let stops = walk.walkStops.count
        let main = [due > 0 ? "\(due) due" : "Nothing due", stops == 1 ? "1 stop" : "\(stops) stops"]
            .joined(separator: " · ")
        var legend = [rhythm.lastTrip.map { "Last \(Restock.ago($0, now: now))" } ?? "No trips yet"]
        if let every = Restock.describe(interval: rhythm.interval) { legend.append(every) }
        return TripLCD(label: label, main: main, number: walk.left, unit: "on list",
                       strip: week(next: rhythm.nextTrip, now: now), legend: legend)
    }

    /// Three days back to three ahead: filled on the days this store was shopped, half on today, outlined on the day
    /// the next trip probably is (today, when it's overdue).
    private func week(next: Date?, now: Date) -> [StripCell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let shopped = Set((store.trips ?? []).filter { !($0.checkOffs ?? []).isEmpty }.compactMap(\.startedAt)
            .map { calendar.startOfDay(for: $0) })
        let nextDay = next.map { max(calendar.startOfDay(for: $0), today) }
        return (-3...3).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let letter = String(day.formatted(.dateTime.weekday(.narrow)))
            let fill: StripCell.Fill = shopped.contains(day) ? .full : offset == 0 ? .half : .empty
            return StripCell(fill: fill, marked: day == nextDay, text: day == nextDay ? "NEXT" : letter)
        }
    }

    // MARK: The list

    /// At home, the list you're building. On a trip, where it went: the List tab.
    @ViewBuilder private func list(_ walk: WalkModel) -> some View {
        if trip == nil {
            HomeListEditor(store: store)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ZoneHeader(title: "You're shopping", count: "\(walk.left) left", state: .next)
                Text("Your list is sorted for the store on the List tab. Tap Back to the trip to carry on.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: What's due

    @ViewBuilder private func dueCards(_ low: [RestockLine], now: Date) -> some View {
        if !low.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ZoneHeader(title: "Due before the next trip", count: "", state: .next)
                    if low.count > 1 {
                        Button("Add all \(low.count)") { add(low.map(\.item)) }
                            .buttonStyle(.sk1Key(size: .small))
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(low, id: \.item.objectID) { line in
                            DueCard(line: line, now: now) { add([line.item]) }
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 1)
                }
                Text("From how often you buy each thing and when you usually shop.")
                    .sk1Hint()
            }
        }
    }

    // MARK: Milestones

    /// What just switched on, announced once.
    @ViewBuilder private func newMilestones(_ milestones: [Milestone]) -> some View {
        let new = milestones.filter { $0.kind == .earned && $0.isDone && !profile.hasSeen($0, of: store) }
        if !new.isEmpty {
            NewMilestones(store: store, milestones: new, onGuide: { guide = GuideJump(id: $0) },
                          onDismiss: { profile.markSeen(new, of: store) })
        }
    }

    /// What's coming: the next few milestones (Checklist), or the level and the next one (Levels).
    @ViewBuilder private func comingUp(_ milestones: [Milestone]) -> some View {
        let done = milestones.filter(\.isDone).count
        let next = Milestones.upNext(milestones)
        switch profile.milestoneStyle {
        case .checklist:
            SKGroup(caption: "Coming up · \(done) of \(milestones.count)",
                    note: next.isEmpty ? "Every feature is on at \(store.displayName)."
                        : "What Buck Fifty learns next at \(store.displayName), and features to try. Tap one for how "
                            + "it works.") {
                ForEach(next.prefix(3)) { milestone in
                    Button { guide = GuideJump(id: milestone.guidePart) } label: { MilestoneRow(milestone: milestone) }
                        .buttonStyle(.plain)
                }
                allMilestones
            }
        case .levels:
            let level = Milestones.level(done: done, of: milestones.count)
            SKGroup(caption: "Your level at \(store.displayName)",
                    note: "It goes up as Buck Fifty learns the store and you try what it can do.") {
                Button { showingMilestones = true } label: {
                    LevelMeter(level: level, total: milestones.count)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Milestones")
                if let first = next.first {
                    Button { guide = GuideJump(id: first.guidePart) } label: { MilestoneRow(milestone: first) }
                        .buttonStyle(.plain)
                }
                allMilestones
            }
        }
    }

    private var allMilestones: some View {
        Button { showingMilestones = true } label: {
            SKRow(title: "All milestones", subtitle: "What it's learned, what's next, and what to try") {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .sk1Ink(soft: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: The last month

    @ViewBuilder private func lastMonth(now: Date) -> some View {
        let since = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let recent = trips.filter { trip in
            trip.store == store && trip.endedAt != nil && (trip.startedAt ?? .distantPast) >= since
                && !(trip.checkOffs ?? []).isEmpty
        }
        if let last = recent.first {
            let bought = recent.reduce(0) { $0 + Set(($1.checkOffs ?? []).compactMap(\.item)).count }
            let minutes = recent.compactMap { trip -> Double? in
                guard let start = trip.startedAt, let end = trip.endedAt else { return nil }
                return end.timeIntervalSince(start) / 60
            }
            let average = minutes.isEmpty ? 0 : Int((minutes.reduce(0, +) / Double(minutes.count)).rounded())
            SKGroup(caption: "Last 30 days") {
                SKRow(title: "Trips", subtitle: "Two people splitting up in the store make two") {
                    SKChip("\(recent.count)", minWidth: 36)
                }
                SKRow(title: "Things bought") { SKChip("\(bought)", minWidth: 36) }
                SKRow(title: "Average trip") { SKChip("\(average) MIN", minWidth: 64) }
                SKRow(title: "Last trip", subtitle: lastTripSubtitle(last)) {
                    SKChip(Restock.ago(last.startedAt ?? now, now: now).uppercased(), minWidth: 64)
                }
            }
        }
    }

    private func lastTripSubtitle(_ trip: Trip) -> String {
        let count = Set((trip.checkOffs ?? []).compactMap(\.item)).count
        var parts = [count == 1 ? "1 thing" : "\(count) things"]
        if let who = trip.shopperName, trip.shopperID != profile.id { parts.append("by \(who)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func add() {
        // A pharmacy locker text pasted in: the pickup, with its code, at the lockers.
        if let pickup = LockerPickup.parse(draft) {
            service.addLockerPickup(pickup, to: store, by: profile.shopper)
            actions.save()
            draft = ""
            return
        }
        guard service.addToList(draft, store: store, by: profile.shopper) != nil else { return }
        actions.save()
        draft = ""
        ZoneGuessing.guessMissing(in: store, context: context)
    }

    private func add(_ items: [Item]) {
        for item in items where !service.isOnList(item) {
            service.addToList(item.displayName, store: store, by: profile.shopper)
        }
        actions.save()
    }

    private func startTrip() {
        if trip == nil { actions.start() }
        navigator.tab = .list
    }
}

/// Something due, as a card: DUE or LATE, how often it's bought, its name and a red Add.
struct DueCard: View {
    let line: RestockLine
    let now: Date
    let add: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                UrgencyTag(text: Restock.chip(line.urgency), late: line.urgency == .overdue)
                Spacer(minLength: 4)
                if let every = Restock.describe(interval: line.estimate.interval) {
                    Text(every.lowercased()).font(.system(size: 11, weight: .semibold)).sk1Ink(soft: true)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Text(line.item.displayName)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .sk1Ink()
            Button(action: add) {
                Text("Add")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Hybrid.redFill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(line.item.displayName)")
        }
        .padding(10)
        .frame(width: 150)
        .background(RoundedRectangle(cornerRadius: 12).fill(Hybrid.card(scheme)))
        .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.08), radius: 1.5, y: 1)
    }
}

/// Home before there's a store: one orange key to add one.
struct NoStoreScreen: View {
    let newStore: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            TripLCD(label: "Buck Fifty", main: "Add a store to start", number: 0, unit: "on list")
            Text("Add a store to start its list. A Costco starts with its zones in walking order.")
                .sk1Hint()
                .multilineTextAlignment(.center)
            Button(action: newStore) { Label("New store", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.sk1Key(.orange, size: .large))
            Spacer()
        }
        .padding(22)
    }
}

/// Choosing the store every tab is about: each store with what's on its list and a lamp while someone is in it.
struct StoreChooserSheet: View {
    let current: Store?
    let newStore: () -> Void
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Navigator.self) private var navigator
    @FetchRequest(fetchRequest: Fetch.stores()) private var stores: FetchedResults<Store>
    @FetchRequest(fetchRequest: Fetch.entries()) private var entries: FetchedResults<ListEntry>
    @FetchRequest(fetchRequest: Fetch.trips()) private var trips: FetchedResults<Trip>

    var body: some View {
        SheetScaffold(title: "Stores", detail: "\(stores.count)") {
            SKGroup(caption: "Shop at", note: "Home, the List, the Map and Restock are all about the store you choose.") {
                ForEach(stores, id: \.objectID) { store in
                    Button { navigator.choose(store) } label: {
                        SKRow(title: store.displayName, subtitle: subtitle(store)) {
                            HStack(spacing: 8) {
                                if trips.contains(where: { $0.store == store && $0.endedAt == nil }) {
                                    SKLamp(color: .teal, lit: true, label: "Someone is in the store", blinking: true)
                                }
                                RadioMark(isOn: store == current)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store == current ? [.isSelected] : [])
                }
            }
        } actions: {
            Button("New store") {
                dismiss()
                newStore()
            }
            .buttonStyle(.sk1Key())
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.sk1Key(.orange))
        }
        .presentationDetents([.medium, .large])
    }

    private func subtitle(_ store: Store) -> String {
        let n = entries.filter { !$0.isChecked && $0.item?.store == store }.count
        let low = ListService(context: context).neededNotOnList(in: store).count
        var parts = [n == 0 ? "Nothing on the list" : n == 1 ? "1 to get" : "\(n) to get"]
        if low > 0 { parts.append("\(low) due") }
        return parts.joined(separator: " · ")
    }
}

/// A new store: its name, and its zones from the defaults.
struct NewStoreSheet: View {
    var created: (Store) -> Void = { _ in }
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        SheetScaffold(title: "New store") {
            CaptionedField(caption: "Name", note: note) {
                SKTextField("Store name", text: $name, prompt: "Costco")
                    .onSubmit(create)
            }
        } actions: {
            Button("Cancel") { dismiss() }.buttonStyle(.sk1Key())
            Spacer()
            Button("Create", action: create)
                .buttonStyle(.sk1Key(.orange))
                .disabled(ItemName.cleaned(name).isEmpty)
        }
        .presentationDetents([.medium])
    }

    private var note: String {
        let zones = DefaultZones.zones(forStoreNamed: name)
        return "Starts with these zones, which you can change: " + zones.joined(separator: ", ") + "."
    }

    private func create() {
        guard !ItemName.cleaned(name).isEmpty else { return }
        let service = ListService(context: context)
        let store = service.createStore(named: name)
        try? service.save()
        created(store)
        dismiss()
    }
}

/// The You tab: your name, how milestones show and all of them, the tour and the guide, trips by location, and Map
/// the store.
struct YouScreen: View {
    /// The store milestones open on.
    let store: Store?
    @Environment(Profile.self) private var profile
    @Environment(Navigator.self) private var navigator
    @State private var showingTour = false
    @State private var showingGuide = false
    @State private var showingMilestones = false
    @Environment(\.scenePhase) private var scenePhase
    private var fence: StoreFence { StoreFence.shared }

    var body: some View {
        @Bindable var profile = profile
        VStack(spacing: 10) {
            ScreenHeader(storeName: store?.displayName, title: profile.name.isEmpty ? "You" : profile.name,
                         chooseStore: { navigator.choosingStore = true }) { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                    CaptionedField(caption: "Your name",
                                   note: "Shown next to what you add and check off, and on your trips.") {
                        SKTextField("Your name", text: $profile.name, prompt: "Jason")
                            .textContentType(.givenName)
                    }
                    SKGroup(caption: "Milestones", note: styleNote) {
                        SKRow(title: "On home") {
                            SKSegmented(selection: $profile.milestoneStyle, options: [
                                SKSegmented<MilestoneStyle>.Option(.checklist, "Checklist",
                                                                   help: "The next few, with progress"),
                                SKSegmented<MilestoneStyle>.Option(.levels, "Levels", help: "A level that rises"),
                            ], height: 30)
                        }
                        Button { showingMilestones = true } label: {
                            SKRow(title: "All milestones", subtitle: "What it's learned, what's next, and what to try") {
                                Image(systemName: "flag.2.crossed").font(.system(size: 14, weight: .medium))
                                    .sk1Ink(soft: true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    SKGroup(caption: "Help") {
                        Button { showingTour = true } label: {
                            SKRow(title: "Tour", subtitle: "A page for every part of the app") {
                                Image(systemName: "play.rectangle").font(.system(size: 14, weight: .medium))
                                    .sk1Ink(soft: true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { showingGuide = true } label: {
                            SKRow(title: "Guide", subtitle: "Every part of the app and every key, to look up") {
                                Image(systemName: "book").font(.system(size: 14, weight: .medium)).sk1Ink(soft: true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    SKGroup(caption: "Trips by location", note: locationNote) {
                        SKRow(title: "Start and end by location", subtitle: "Starts as you arrive, ends as you leave") {
                            Toggle(isOn: $profile.tripsFollowLocation) { EmptyView() }
                                .toggleStyle(.sk1Switch)
                                .accessibilityLabel("Start and end trips by location")
                        }
                        if profile.tripsFollowLocation, let store {
                            SKRow(title: store.displayName, subtitle: pinSubtitle(store)) {
                                Button(fence.isLocating ? "Finding…" : "Pin here") { fence.pinHere(store) }
                                    .buttonStyle(.sk1Key(size: .small))
                                    .disabled(fence.isLocating)
                                    .accessibilityLabel("Pin \(store.displayName) where you are now")
                            }
                            if let pin = fence.pin(for: store) {
                                SKRow(title: "Radius") {
                                    SKSegmented(selection: Binding(get: { pin.radius },
                                                                   set: { fence.setRadius($0, for: store) }),
                                                options: StorePin.radii.map { radius in
                                                    SKSegmented<Double>.Option(radius, "\(Int(radius)) m",
                                                                               help: radiusHelp(radius))
                                                }, height: 30)
                                }
                            }
                        }
                    }
                    .onChange(of: profile.tripsFollowLocation) { _, on in fence.setOn(on) }
                    SKGroup(caption: "Experimental", note: mappingNote) {
                        SKRow(title: "Map the store", subtitle: "Builds a floor plan from your trips") {
                            Toggle(isOn: $profile.mapsStore) { EmptyView() }
                                .toggleStyle(.sk1Switch)
                                .disabled(!StoreMapper.isAvailable)
                                .accessibilityLabel("Map the store")
                        }
                    }
                    .onChange(of: profile.mapsStore) { _, on in
                        if on { StoreMapper.requestAccess() }
                    }
                }
                .padding(.horizontal, SK1.Metrics.paneMargin)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.top, 4)
        .sheet(isPresented: $showingGuide) { GuideSheet() }
        .sheet(isPresented: $showingMilestones) { MilestonesSheet(store: store) }
        .fullScreenCover(isPresented: $showingTour) { TourSheet() }
        .onAppear {
            fence.refresh()
            guard Launch.isDemo else { return }
            showingMilestones = Launch.demoScreen.hasPrefix("milestones")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { fence.refresh() }
        }
    }

    private func pinSubtitle(_ store: Store) -> String {
        guard let pin = fence.pin(for: store) else {
            return "Not pinned yet: tap Pin here in the store, or Start trip there"
        }
        return "Pinned, with \(Int(pin.radius)) m around it"
    }

    private func radiusHelp(_ radius: Double) -> String {
        switch radius {
        case ..<150: return "A small store"
        case ..<300: return "A big store and its car park"
        default: return "A big store in a wide car park"
        }
    }

    private var locationNote: String {
        guard profile.tripsFollowLocation, !Launch.isDemo else {
            return "Walk into a store you've pinned and a trip starts, if there's something on the list. Leave, and "
                + "it ends, even if you forgot to tap Done."
        }
        switch fence.authorization {
        case .denied, .restricted:
            return "Location is off for Buck Fifty. Turn it on in Settings, Buck Fifty, Location, and choose Always."
        case .authorizedWhenInUse:
            return "Location is only While Using the App, so a trip only ends as you leave with the app open. Choose "
                + "Always in Settings, Buck Fifty, Location, for it to work with the app closed."
        default:
            return "A trip starts as you arrive at a pinned store with something on the list, and ends as you leave, "
                + "even with the app closed. Pins stay on this phone; your location never leaves it."
        }
    }

    private var styleNote: String {
        switch profile.milestoneStyle {
        case .checklist:
            return "Home shows what Buck Fifty learns next and features to try, each with how far along it is."
        case .levels:
            return "Home shows your level, which goes up as Buck Fifty learns the store and you try its features."
        }
    }

    private var mappingNote: String {
        guard StoreMapper.isAvailable else { return "This iPhone has no pedometer or compass to map with." }
        return "Tap Start trip at the door and keep the app open: your steps and compass trace your walk, and every "
            + "check-off becomes a point. After about ten trips the floor plan key shows where everything is. Steel "
            + "shelves bend the compass, so expect it to wander. It asks for Motion & Fitness access; the walk stays "
            + "on this phone and in your shared list."
    }
}
