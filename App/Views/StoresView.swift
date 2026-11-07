import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// The home screen: a dashboard for the next trip. The LCD says which store is next and how much is on its list; a
/// week strip shows the days you shopped and the day the next trip probably is; the tiles go shopping or restock;
/// then what's running low at every store (one tap puts it on its list), each store with its rhythm, and the last
/// month's trips in numbers.
struct StoresView: View {
    @Binding var path: [ListRoute]
    @Environment(\.managedObjectContext) private var context
    @Environment(Profile.self) private var profile
    @Environment(SharingModel.self) private var sharing
    @FetchRequest(fetchRequest: Fetch.stores()) private var stores: FetchedResults<Store>
    // Fetched so the screen redraws when any list or trip changes, here or on the other person's phone.
    @FetchRequest(fetchRequest: Fetch.entries()) private var entries: FetchedResults<ListEntry>
    @FetchRequest(fetchRequest: Fetch.trips()) private var trips: FetchedResults<Trip>
    @State private var showingNewStore = false
    @State private var showingProfile = false

    private var service: ListService { ListService(context: context) }

    var body: some View {
        let now = Date()
        let glances = stores.map { glance($0, now: now) }
        let focus = focusGlance(glances)
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                VStack(spacing: 10) {
                    hero(focus, now: now)
                    WeekStrip(shopped: shoppedDays, nextTrip: focus?.rhythm.nextTrip, now: now)
                    tiles(focus)
                }
                runningLow(glances, now: now)
                storeList(glances, now: now)
                lastMonth(now: now)
            }
            .padding(16)
        }
        .sk1Chassis()
        .navigationTitle("Buck Fifty")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNewStore) { NewStoreSheet() }
        .sheet(isPresented: $showingProfile) { ProfileSheet() }
    }

    // MARK: What each store looks like right now

    /// What the home screen says about one store, worked out once a draw.
    private struct Glance {
        let store: Store
        let toGet: Int
        /// Running low and not on the list yet, most urgent first.
        let low: [RestockLine]
        let rhythm: ShoppingRhythm
        /// Other people shopping it right now.
        let shoppers: [String]
        /// Whether you're on a trip there.
        let mine: Bool
    }

    private func glance(_ store: Store, now: Date) -> Glance {
        let open = trips.filter { trip in
            trip.store == store && trip.endedAt == nil
                && !service.policy.hasLapsed(lastActivity: trip.lastActivityAt ?? trip.startedAt ?? now, now: now)
        }
        return Glance(store: store,
                      toGet: entries.filter { !$0.isChecked && $0.item?.store == store }.count,
                      low: service.neededNotOnList(in: store, now: now),
                      rhythm: service.rhythm(of: store),
                      shoppers: open.filter { $0.shopperID != profile.id }.compactMap(\.shopperName),
                      mine: open.contains { $0.shopperID == profile.id })
    }

    /// The store the screen is about: the one you're in, else the one someone else is in, else the one with the
    /// most running low, else the one due a trip soonest.
    private func focusGlance(_ glances: [Glance]) -> Glance? {
        if let mine = glances.first(where: \.mine) { return mine }
        if let shared = glances.first(where: { !$0.shoppers.isEmpty }) { return shared }
        return glances.min { a, b in
            if a.low.count != b.low.count { return a.low.count > b.low.count }
            return (a.rhythm.nextTrip ?? .distantFuture) < (b.rhythm.nextTrip ?? .distantFuture)
        }
    }

    /// The days anything was bought, at any store.
    private var shoppedDays: Set<Date> {
        let calendar = Calendar.current
        return Set(trips.filter { !($0.checkOffs ?? []).isEmpty }.compactMap(\.startedAt).map { calendar.startOfDay(for: $0) })
    }

    // MARK: The LCD and tiles

    private func hero(_ focus: Glance?, now: Date) -> some View {
        let low = focus?.low.count ?? 0
        let message = stores.isEmpty ? "No stores" : low > 0 ? "\(low) low" : "All set"
        return SKDisplay(title: focus?.store.displayName ?? "Buck Fifty",
                         detail: focus.map { heroDetail($0, now: now) } ?? "ADD A STORE TO START",
                         message: message,
                         number: focus?.toGet, digits: 3, unit: "TO GET",
                         live: focus.map { $0.mine || !$0.shoppers.isEmpty } ?? false)
    }

    private func heroDetail(_ focus: Glance, now: Date) -> String {
        if focus.mine { return "YOU'RE IN THE STORE" }
        if let other = focus.shoppers.first { return "\(other.uppercased()) IN THE STORE" }
        if let next = focus.rhythm.nextTrip { return "NEXT TRIP \(Restock.until(next, now: now).uppercased())" }
        if let last = focus.rhythm.lastTrip { return "LAST TRIP \(Restock.ago(last, now: now).uppercased())" }
        return "NO TRIPS YET"
    }

    /// The main actions: go shopping at the store in focus (orange), restock it, add a store, and you.
    private func tiles(_ focus: Glance?) -> some View {
        SKWell {
            HStack(spacing: 4) {
                if let focus {
                    SKTile(focus.mine ? "Resume" : "Shop", systemImage: "cart", variant: .orange) {
                        path.append(ListRoute(store: focus.store))
                    }
                    SKTile("Restock", systemImage: "checklist", isOn: !focus.low.isEmpty) {
                        path.append(ListRoute(store: focus.store, mode: .restock))
                    }
                    SKTile("New store", systemImage: "plus") { showingNewStore = true }
                } else {
                    SKTile("New store", systemImage: "plus", variant: .orange) { showingNewStore = true }
                }
                SKTile(profile.name.isEmpty ? "You" : profile.name, systemImage: "person.crop.circle") {
                    showingProfile = true
                }
            }
            .padding(6)
        }
    }

    // MARK: Running low

    /// One running-low item and its store.
    private struct Low: Identifiable {
        let store: Store
        let line: RestockLine
        var id: NSManagedObjectID { line.item.objectID }
    }

    @ViewBuilder private func runningLow(_ glances: [Glance], now: Date) -> some View {
        let low = glances.flatMap { glance in glance.low.map { Low(store: glance.store, line: $0) } }
            .sorted { Restock.precedes(($0.line.urgency, $0.line.estimate, $0.line.item.displayName),
                                       ($1.line.urgency, $1.line.estimate, $1.line.item.displayName)) }
        if !low.isEmpty {
            SKGroup(caption: "Running low · \(low.count)",
                    note: "From how often you buy each thing and when you usually shop. Add puts it on its list.") {
                ForEach(low.prefix(6)) { entry in
                    SKRow(title: entry.line.item.displayName, subtitle: lowSubtitle(entry, now: now)) {
                        Button("Add") { add([entry.line.item]) }
                            .buttonStyle(.sk1Key(size: .small))
                            .accessibilityLabel("Add \(entry.line.item.displayName) to \(entry.store.displayName)")
                    }
                }
                if low.count > 1 {
                    SKRow(title: "Everything running low",
                          subtitle: stores.count > 1 ? "Each onto its own store's list" : nil) {
                        Button("Add all \(low.count)") { add(low.map(\.line.item)) }
                            .buttonStyle(.sk1Key(size: .small))
                    }
                }
            }
        } else if !stores.isEmpty {
            SKWell {
                Text(glances.contains { $0.rhythm.tripDays > 0 }
                     ? "Nothing's running low. Restock lists everything you've bought, with how often you buy it."
                     : "Shop a couple of times and Buck Fifty learns how often you buy each thing, then lists what's "
                        + "running low here before you go.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SK1.Metrics.rowInset)
            }
        }
    }

    private func lowSubtitle(_ entry: Low, now: Date) -> String {
        var parts: [String] = []
        if stores.count > 1 { parts.append(entry.store.displayName) }
        if entry.line.urgency == .overdue { parts.append("Overdue") }
        parts.append(entry.line.summary(now: now))
        return parts.joined(separator: " · ")
    }

    // MARK: Stores

    @ViewBuilder private func storeList(_ glances: [Glance], now: Date) -> some View {
        if glances.isEmpty {
            SKWell {
                Text("Add a store to start its list. A Costco starts with its zones in walking order.")
                    .sk1Hint()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SK1.Metrics.rowInset)
            }
        } else {
            SKGroup(caption: "Stores") {
                ForEach(glances, id: \.store.objectID) { glance in
                    NavigationLink(value: ListRoute(store: glance.store)) {
                        SKRow(title: glance.store.displayName, subtitle: storeSubtitle(glance, now: now)) {
                            HStack(spacing: 8) {
                                if glance.mine || !glance.shoppers.isEmpty {
                                    SKLamp(color: .teal, lit: true, label: inStoreLabel(glance), blinking: true)
                                }
                                SKChip("\(glance.toGet)", minWidth: 36)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func inStoreLabel(_ glance: Glance) -> String {
        let people = (glance.mine ? ["You"] : []) + glance.shoppers
        return people.joined(separator: " and ") + " in the store"
    }

    private func storeSubtitle(_ glance: Glance, now: Date) -> String {
        let n = glance.toGet
        var parts = [n == 0 ? "Nothing on the list" : n == 1 ? "1 to get" : "\(n) to get"]
        if !glance.low.isEmpty { parts.append("\(glance.low.count) running low") }
        if let next = glance.rhythm.nextTrip {
            parts.append("next trip \(Restock.until(next, now: now))")
        } else if let last = glance.rhythm.lastTrip {
            parts.append("last trip \(Restock.ago(last, now: now))")
        }
        let share = sharing.summary(for: glance.store)
        if share.isShared { parts.append("shared with \(share.people)") }
        return parts.joined(separator: " · ")
    }

    // MARK: The last month

    @ViewBuilder private func lastMonth(now: Date) -> some View {
        let since = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let recent = trips.filter { trip in
            trip.endedAt != nil && (trip.startedAt ?? .distantPast) >= since && !(trip.checkOffs ?? []).isEmpty
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
        var parts = [trip.store?.displayName ?? "", count == 1 ? "1 thing" : "\(count) things"]
        if let who = trip.shopperName, trip.shopperID != profile.id { parts.append("by \(who)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Actions

    private func add(_ items: [Item]) {
        for item in items where !service.isOnList(item) {
            if let store = item.store { service.addToList(item.displayName, store: store, by: profile.shopper) }
        }
        do { try service.save() } catch {
            context.rollback()
            print("Buck Fifty: save failed: \(error)")
        }
    }
}

/// The week on LCD glass: three days back to three ahead, a dot under the days anything was bought and NEXT under
/// the day the next trip probably is (today, when it's overdue). Today is lit in reverse.
struct WeekStrip: View {
    let shopped: Set<Date>
    let nextTrip: Date?
    let now: Date
    private let calendar = Calendar.current

    var body: some View {
        let today = calendar.startOfDay(for: now)
        let next = nextTrip.map { max(calendar.startOfDay(for: $0), today) }
        SKLCD {
            HStack(spacing: 2) {
                ForEach(-3...3, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
                    cell(day, isToday: offset == 0, shopped: shopped.contains(day), isNext: day == next)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(height: 64)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("This week")
    }

    private func cell(_ day: Date, isToday: Bool, shopped: Bool, isNext: Bool) -> some View {
        let ink = Color(sk1Hex: isToday ? SK1.glassTop : SK1.lcdInk)
        return VStack(spacing: 1) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 8.5, weight: .heavy))
                .tracking(1)
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
            Text(isNext ? "NEXT" : shopped ? "●" : " ")
                .font(.system(size: 7.5, weight: .heavy))
                .tracking(0.6)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isToday { RoundedRectangle(cornerRadius: 4).fill(Color(sk1Hex: SK1.lcdInk, opacity: 0.85)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(day, isToday: isToday, shopped: shopped, isNext: isNext))
    }

    private func accessibilityLabel(_ day: Date, isToday: Bool, shopped: Bool, isNext: Bool) -> String {
        var parts = [isToday ? "Today" : day.formatted(.dateTime.weekday(.wide).day())]
        if shopped { parts.append("shopped") }
        if isNext { parts.append("next trip") }
        return parts.joined(separator: ", ")
    }
}

/// A new store: its name, and its zones from the defaults.
struct NewStoreSheet: View {
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
        service.createStore(named: name)
        try? service.save()
        dismiss()
    }
}

/// Your name, as the people you share a list with see it.
struct ProfileSheet: View {
    @Environment(Profile.self) private var profile
    @Environment(SharingModel.self) private var sharing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var profile = profile
        SheetScaffold(title: "You", detail: profile.shopper.initials) {
            CaptionedField(caption: "Your name",
                           note: "Shown next to what you add and check off, and on your trips.") {
                SKTextField("Your name", text: $profile.name, prompt: "Jason")
                    .textContentType(.givenName)
                    .onSubmit { dismiss() }
            }
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
        } actions: {
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.sk1Key(.orange))
        }
    }

    private var mappingNote: String {
        guard StoreMapper.isAvailable else { return "This iPhone has no pedometer or compass to map with." }
        return "Tap Start trip at the door and keep the app open: your steps and compass trace your walk, and every "
            + "check-off becomes a point. After about ten trips the map shows where everything is. Steel shelves "
            + "bend the compass, so expect it to wander. It asks for Motion & Fitness access; the walk stays on this "
            + "phone and in your shared list."
    }
}
