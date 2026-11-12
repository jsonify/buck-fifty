import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// The entry the edit sheet is open on. Core Data objects aren't Identifiable here, so `sheet(item:)` gets this.
struct Editing: Identifiable {
    let entry: ListEntry
    var id: NSManagedObjectID { entry.objectID }
}

/// One row of a stop, for `ForEach`: the row, its walk number and where it is on its card.
struct StopRow: Identifiable {
    let row: ListRow
    let number: Int?
    let index: Int
    var id: NSManagedObjectID { row.entry.objectID }

    static func rows(of stop: Walk.Stop<ListRow>) -> [StopRow] {
        zip(stop.entries, stop.numbers).enumerated().map { StopRow(row: $1.0, number: $1.1, index: $0) }
    }
}

/// The List tab. At home it's a plain list in your own order (`HomeOrder`): type things in one after another, drag
/// them around, and open Past items to tap on what you've bought before. In the store it becomes the walk (issue
/// #25): the LCD says what's next and how many are left, with the walk's stops on its strip; each stop hangs off the
/// route rail in walking order (blue once done, orange for the next one), its items on a white card with their walk
/// numbers, the same numbers as the pins on the Map. Checked items stay in their zone, struck through. Hold an item
/// and drag it onto another to move it. A switch over the list shows it A to Z instead (`ListGrouping`).
struct ListScreen: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(Profile.self) private var profile
    @Environment(SharingModel.self) private var sharing
    @Environment(Navigator.self) private var navigator
    @FetchRequest private var entries: FetchedResults<ListEntry>
    @FetchRequest private var zones: FetchedResults<Zone>
    @FetchRequest private var items: FetchedResults<Item>
    @FetchRequest private var openTrips: FetchedResults<Trip>
    @State private var draft = ""
    @State private var editing: Editing?
    @State private var showingZones = false
    @State private var showingFloorPlan = false
    /// The Everything screen: the last trip and every remembered item.
    @State private var showingEverything = false
    /// Everything opened by Done: it starts with what the trip didn't get.
    @State private var reviewingTrip = false
    /// Past items: everything bought before, to tap onto the list.
    @State private var showingPast = false
    @State private var appliedDemo = false
    /// The row a dragged item is over: it will take that row's place.
    @State private var dropTarget: NSManagedObjectID?

    init(store: Store) {
        self.store = store
        _entries = FetchRequest(fetchRequest: Fetch.entries(in: store))
        _zones = FetchRequest(fetchRequest: Fetch.zones(in: store))
        _items = FetchRequest(fetchRequest: Fetch.items(in: store))
        _openTrips = FetchRequest(fetchRequest: Fetch.openTrips(in: store))
    }

    private var service: ListService { ListService(context: context) }
    private var actions: TripActions { TripActions(store: store, context: context, profile: profile) }
    private var mapper: StoreMapper { StoreMapper.shared }
    private var trip: Trip? { service.activeTrip(among: Array(openTrips), for: profile.shopper) }
    private var share: ShareSummary { sharing.summary(for: store) }

    var body: some View {
        let walk = WalkModel(entries: Array(entries), zones: Array(zones), items: Array(items))
        VStack(spacing: 10) {
            ScreenHeader(storeName: store.displayName, title: "Shopping list",
                         chooseStore: { navigator.choosingStore = true }) {
                StorePresencePill(store: store, openTrips: Array(openTrips))
            }
            walk.lcd(trip: trip, store: store, now: Date())
                .padding(.horizontal, 14)
            AddBar(draft: $draft, prompt: "Add to \(store.displayName)…") { add(draft) }
                .padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !draftIsBlank {
                        suggestionList.padding(.horizontal, 4)
                    } else {
                        pastItemsKey.padding(.horizontal, 4).padding(.bottom, 12)
                        if walk.rows.isEmpty {
                            Text("A clean list. Type above, one thing after another, or open Past items and tap what "
                                 + "you've bought before.")
                                .sk1Hint()
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                        } else {
                            groupingSwitch.padding(.horizontal, 4).padding(.bottom, 12)
                        }
                        if profile.listGrouping == .alphabetical {
                            if !walk.rows.isEmpty { alphabeticalList(walk).padding(.horizontal, 4) }
                        } else if trip == nil {
                            if !walk.rows.isEmpty { homeList(walk).padding(.horizontal, 4) }
                        } else {
                            ForEach(walk.stops, id: \.id) { stop in
                                stopView(stop, walk: walk)
                            }
                        }
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 14)
                .padding(.vertical, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            TripBar(title: tripTitle, systemImage: trip == nil ? "cart" : "checkmark", action: toggleTrip) {
                Button { showingZones = true } label: { Image(systemName: "square.stack.3d.up") }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("Zones")
                Button { showingEverything = true } label: { Image(systemName: "tray.full") }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("Everything: the last trip and every item this store remembers")
                if profile.mapsStore {
                    Button { showingFloorPlan = true } label: { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath") }
                        .buttonStyle(.sk1Key(isOn: mapper.isRecording(trip)))
                        .accessibilityLabel(mapper.isRecording(trip) ? "Floor plan, mapping this trip" : "Floor plan")
                }
                ShareKey(store: store)
            }
        }
        .padding(.top, 4)
        .sheet(item: $editing) { EditEntrySheet(entry: $0.entry, zones: Array(zones)) }
        .sheet(isPresented: $showingZones) { ZonesSheet(store: store) }
        .sheet(isPresented: $showingFloorPlan) { FloorPlanSheet(store: store) }
        .sheet(isPresented: $showingEverything, onDismiss: { reviewingTrip = false }) {
            EverythingSheet(store: store, showsLeftovers: reviewingTrip)
        }
        .sheet(isPresented: $showingPast) { PastItemsSheet(store: store) }
        .onAppear {
            actions.endLapsedTrips()
            ZoneGuessing.guessMissing(in: store, context: context)
            applyDemoScreen()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { actions.endLapsedTrips() }
        }
    }

    private var tripTitle: String {
        guard trip != nil else { return "Start trip" }
        let inCart = entries.filter { $0.isChecked && $0.checkedByID == profile.id }.count
        return "Done · \(inCart) in cart"
    }

    // MARK: The walk

    /// One stop: its node on the rail (and the rail on down to the next), its heading and its card.
    private func stopView(_ stop: Walk.Stop<ListRow>, walk: WalkModel) -> some View {
        let p = SK1.palette(for: scheme)
        let nextID = walk.next?.entry.entry.objectID
        return HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 2) {
                RailNode(text: WalkModel.railLabel(stop), state: stop.state)
                Rectangle()
                    .fill(stop.state == .done ? Hybrid.blueFill : Color(sk1Hex: p.inkSoft).opacity(0.3))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                ZoneHeader(title: stopTitle(stop), count: stop.left == 0 ? "All in" : "\(stop.left) left",
                           state: stop.state)
                ListCard {
                    ForEach(StopRow.rows(of: stop)) { item in
                        walkRow(item, isNext: item.id == nextID)
                    }
                }
                if stop.kind == .lookForIt {
                    Text("These move around the store, so they're not in the walk. Keep an eye out for them.")
                        .sk1Hint()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 14)
        }
    }

    private func stopTitle(_ stop: Walk.Stop<ListRow>) -> String {
        stop.state == .next && trip != nil ? "\(stop.title) · next" : stop.title
    }

    /// The switch over the list: your own order at home (a stop per zone in walking order in the store), or
    /// everything A to Z.
    private var groupingSwitch: some View {
        let grouping = Binding(get: { profile.listGrouping }, set: { profile.listGrouping = $0 })
        let first = trip == nil
            ? SKSegmented<ListGrouping>.Option(.zone, "My order", help: "The order you put it in; drag to move")
            : SKSegmented<ListGrouping>.Option(.zone, "By zone", help: "A stop per zone, in walking order")
        return SKSegmented(selection: grouping, options: [
            first,
            SKSegmented<ListGrouping>.Option(.alphabetical, "A to Z", help: "Everything on one card, by name"),
        ], height: 30)
    }

    /// The list A to Z on one card: no rail and no walk numbers, each row saying its zone. Checked items stay in
    /// place, struck through.
    private func alphabeticalList(_ walk: WalkModel) -> some View {
        let rows = ListOrdering.alphabetical(walk.rows)
        return VStack(alignment: .leading, spacing: 6) {
            ZoneHeader(title: "A to Z", count: walk.left == 0 ? "All in" : "\(walk.left) left",
                       state: walk.left == 0 ? .done : .ahead)
            ListCard {
                ForEach(Array(rows.enumerated()), id: \.element.entry.objectID) { index, row in
                    itemRow(row, number: nil, index: index, isNext: false, showsZone: true)
                }
            }
        }
        .padding(.bottom, 14)
    }

    /// The list at home: one card in your own order, no rail and no walk numbers. Hold an item and drag it onto
    /// another to move it there.
    private func homeList(_ walk: WalkModel) -> some View {
        let rows = HomeOrder.sorted(walk.rows)
        return VStack(alignment: .leading, spacing: 6) {
            ZoneHeader(title: "Your order", count: walk.left == 0 ? "All in" : "\(walk.left) to get",
                       state: walk.left == 0 ? .done : .ahead)
            ListCard {
                ForEach(Array(rows.enumerated()), id: \.element.entry.objectID) { index, row in
                    movable(itemRow(row, number: nil, index: index, isNext: false, showsZone: false),
                            entry: row.entry) { moveAtHome($0, onto: row.entry) }
                }
            }
            Text("In the store it sorts itself into the order you walk it.")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 14)
    }

    /// A row of the walk: it can be dragged onto another to move it in the walk.
    private func walkRow(_ item: StopRow, isNext: Bool) -> some View {
        let entry = item.row.entry
        return movable(itemRow(item.row, number: item.number, index: item.index, isNext: isNext, showsZone: false),
                       entry: entry) { move($0, onto: entry) }
    }

    /// `row`, which can be held and dragged onto another row (`drop` gets the dragged entry's id), outlined in orange
    /// while something is over it.
    private func movable<Row: View>(_ row: Row, entry: ListEntry,
                                    drop: @escaping (String?) -> Bool) -> some View {
        row
            .draggable(entry.id?.uuidString ?? "") { SKChip(entry.displayName) }
            .dropDestination(for: String.self) { ids, _ in
                drop(ids.first)
            } isTargeted: { over in
                if over {
                    dropTarget = entry.objectID
                } else if dropTarget == entry.objectID {
                    dropTarget = nil
                }
            }
            .overlay {
                if dropTarget == entry.objectID {
                    RoundedRectangle(cornerRadius: 6).stroke(Hybrid.orange, lineWidth: 2)
                }
            }
    }

    /// An item: tap to check it off, hold to edit or remove it. With `showsZone` (A to Z) its detail starts with its
    /// zone.
    private func itemRow(_ row: ListRow, number: Int?, index: Int, isNext: Bool, showsZone: Bool) -> some View {
        let entry = row.entry
        let guessed = entry.item?.isZoneGuessed == true && !entry.isChecked
        let lookFor = self.lookFor(row)
        let zone = showsZone && lookFor == nil ? entry.item?.storeZone?.displayName ?? ListOrdering.unzonedTitle : nil
        return ItemRow(name: entry.displayName, detail: detail(entry, lookFor: lookFor, zone: zone),
                       detailTone: lookFor != nil ? .alert : .soft, quantity: entry.quantity,
                       isChecked: entry.isChecked, number: number, isNext: isNext,
                       showsDivider: index > 0,
                       accessory: guessed ? AnyView(guessedChip(entry)) : nil,
                       toggle: { actions.toggle(entry) })
            .onTapGesture { actions.toggle(entry) }
            .contextMenu {
                Button("Edit", systemImage: "pencil") { editing = Editing(entry: entry) }
                Button("Remove from list", systemImage: "trash", role: .destructive) { remove(entry) }
            }
            .accessibilityAction(named: "Edit") { editing = Editing(entry: entry) }
    }

    private func guessedChip(_ entry: ListEntry) -> some View {
        Button { editing = Editing(entry: entry) } label: { SKChip("GUESSED", minWidth: 64) }
            .buttonStyle(.plain)
            .accessibilityLabel("Zone guessed: \(entry.item?.storeZone?.displayName ?? ""). Edit")
    }

    /// Where an item under Look for it has been seen, or nil for every other row.
    private func lookFor(_ row: ListRow) -> String? {
        guard !row.isChecked, row.isWandering, let item = row.entry.item else { return nil }
        let seen = service.wanderNote(for: item) ?? "Moves around"
        if let zone = item.storeZone?.displayName { return "\(seen) · \(zone)" }
        return seen
    }

    /// The zone (A to Z only), the note, and on a shared list who added it or has it in their cart when that isn't
    /// you.
    private func detail(_ entry: ListEntry, lookFor: String?, zone: String? = nil) -> String? {
        var parts: [String] = []
        if let lookFor { parts.append(lookFor) }
        if let zone { parts.append(zone) }
        if let note = entry.note, !note.isEmpty { parts.append(note) }
        if share.isShared {
            if entry.isChecked, let id = entry.checkedByID, id != profile.id, let name = entry.checkedByName {
                parts.append("In \(name)'s cart")
            } else if !entry.isChecked, let id = entry.addedByID, id != profile.id, let name = entry.addedByName {
                parts.append("Added by \(name)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Adding

    /// Opens Past items: everything bought before, to tap onto the list. Kept off the list itself, so a new list
    /// starts clean.
    private var pastItemsKey: some View {
        Button { showingPast = true } label: {
            Label("Past items", systemImage: "clock.arrow.circlepath")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.sk1Key())
        .accessibilityHint("Everything you've bought before, to tap onto the list")
    }

    private var draftIsBlank: Bool { ItemName.cleaned(draft).isEmpty }

    /// While typing: what the store remembers that matches, to add with one tap.
    @ViewBuilder private var suggestionList: some View {
        let matches = ItemSuggester.suggestions(for: draft, in: Array(items), limit: 6) { $0.displayName }
        let exact = matches.first { $0.normalizedName == ItemName.normalized(draft) }
        SKGroup(caption: "Add") {
            if exact == nil {
                Button { add(draft) } label: {
                    SKRow(title: ItemName.cleaned(draft), subtitle: "New item") { SKChip("NEW") }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(matches, id: \.objectID) { item in
                Button { add(item.displayName) } label: {
                    SKRow(title: item.displayName, subtitle: item.storeZone?.displayName ?? ListOrdering.unzonedTitle) {
                        SKChip(onList(item) ? "+1" : "ADD")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func onList(_ item: Item) -> Bool {
        (item.entries ?? []).contains { !$0.isChecked && !$0.isDeleted }
    }

    // MARK: Actions

    private func add(_ name: String) {
        guard service.addToList(name, store: store, by: profile.shopper) != nil else { return }
        actions.save()
        draft = ""
        // The zone is guessed in the background: adding never waits for it.
        ZoneGuessing.guessMissing(in: store, context: context)
    }

    /// Moves the dragged entry (by its id) to `target`'s place in the walk: it gets a position between its new
    /// neighbours, and `target`'s zone if it has one.
    private func move(_ id: String?, onto target: ListEntry) -> Bool {
        dropTarget = nil
        let walk = WalkModel(entries: Array(entries), zones: Array(zones), items: Array(items))
        let rows = walk.unchecked
        guard let id, let from = rows.firstIndex(where: { $0.entry.id?.uuidString == id }),
              let to = rows.firstIndex(where: { $0.entry == target }), from != to,
              let item = rows[from].entry.item else { return false }
        let keys = ListOrdering.walkPositions(rows, zoneCount: walk.zoneNames.count, zonePositions: walk.zonePositions)
        var positions: [Item: Double] = [:]
        for (index, position) in ListOrdering.positionsAfterMove(keys, from: from, to: to) {
            if let moved = rows[index].entry.item { positions[moved] = position }
        }
        if let zone = target.item?.storeZone, zone != item.storeZone { service.setZone(zone, for: item) }
        service.place(positions, moved: item)
        actions.save()
        profile.markTried(Milestones.Try.drag)
        return true
    }

    /// Moves the dragged entry (by its id) to `target`'s place in your own order, at home.
    private func moveAtHome(_ id: String?, onto target: ListEntry) -> Bool {
        dropTarget = nil
        let list = HomeOrder.sorted(Array(entries))
        guard let id, let from = list.firstIndex(where: { $0.id?.uuidString == id }),
              let to = list.firstIndex(of: target), from != to else { return false }
        service.moveAtHome(list, from: from, to: to)
        actions.save()
        profile.markTried(Milestones.Try.drag)
        return true
    }

    private func remove(_ entry: ListEntry) {
        service.remove(entry)
        actions.save()
    }

    private func toggleTrip() {
        if trip == nil {
            actions.start()
        } else if actions.finish(trip) {
            // What you bought comes off the list; the trip's review starts with what you didn't get (to keep for
            // next time or drop) and is where to set zones and fix the order.
            reviewingTrip = true
            showingEverything = true
        }
    }

    private func applyDemoScreen() {
        guard Launch.isDemo, !appliedDemo else { return }
        appliedDemo = true
        switch Launch.demoScreen {
        case "add": draft = "chi"
        case "zones": showingZones = true
        case "floorplan": showingFloorPlan = true
        case "everything": showingEverything = true
        case "past": showingPast = true
        case "edit", "zone": editing = entries.first { $0.displayName == "Coffee beans" }.map(Editing.init)
        default: break
        }
    }
}

/// Who else is in the store (a lit teal lamp), else who the list is shared with.
struct StorePresencePill: View {
    @ObservedObject var store: Store
    let openTrips: [Trip]
    @Environment(\.managedObjectContext) private var context
    @Environment(Profile.self) private var profile
    @Environment(SharingModel.self) private var sharing

    var body: some View {
        let service = ListService(context: context)
        let others = openTrips.filter { other in
            other.shopperID != profile.id
                && service.activeTrip(among: [other], for: Shopper(id: other.shopperID ?? "", name: "")) != nil
        }
        .compactMap(\.shopperName)
        let share = sharing.summary(for: store)
        if let other = others.first {
            PresencePill(text: "\(other) is here", lit: true)
        } else if share.isShared {
            PresencePill(text: "Shared with \(share.people)", lit: false)
        }
    }
}

/// The Share key: invites someone to the store's list, lit once it's shared.
struct ShareKey: View {
    @ObservedObject var store: Store
    @Environment(SharingModel.self) private var sharing

    var body: some View {
        let share = sharing.summary(for: store)
        Button {
            Task { await sharing.presentSharing(for: store) }
        } label: {
            Image(systemName: share.isShared ? "person.2.fill" : "person.badge.plus")
        }
        .buttonStyle(.sk1Key(isOn: share.isShared))
        .disabled(sharing.isWorking)
        .accessibilityLabel(share.isShared ? "Shared with \(share.people)" : "Share this list")
    }
}

extension WalkModel {
    /// The LCD on the List and the Map: in the store, how long you've been there, what's next and how many are left,
    /// the stops on the strip; at home, how many stops the list makes and how many things are on it.
    func lcd(trip: Trip?, store: Store, now: Date) -> TripLCD {
        let stopCount = walkStops.count
        if let trip {
            let minutes = Int(now.timeIntervalSince(trip.startedAt ?? now) / 60)
            let main = next.map { "Next \($0.number) · \($0.entry.entry.displayName)" } ?? "All in · tap Done"
            let middle = nextStop?.title ?? "Checkout"
            return TripLCD(label: "In the store · \(minutes) min", main: main, number: left, unit: "left",
                           strip: strip, legend: ["Entry", middle, "Exit"])
        }
        let main = left == 0 ? "A clean list" : stopCount == 1 ? "1 stop in the walk" : "\(stopCount) stops in the walk"
        return TripLCD(label: "At home · \(store.displayName)", main: main, number: left, unit: "on list",
                       strip: strip, legend: ["Entry", "In walking order", "Exit"])
    }
}
