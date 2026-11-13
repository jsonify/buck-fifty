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

/// The List tab. At home it's the list you're building (`HomeListEditor`): Select from inventory, type to add, drag to
/// reorder, the trash to take something off. No check marks, and nothing starts a trip but Start trip. In the store,
/// after Start trip, it sorts itself into a card per zone in the order you picked things up last time, and every row
/// has three buttons, explained over the list: the circle (got it, struck through), Not here (the store didn't have it:
/// it moves to Not here at the bottom and stays on the list for next time) and the trash (changed your mind). Done
/// takes what you got off the list; the rest stays for next time.
struct ListScreen: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
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
        let split = profile.notHere.split(Array(entries)) { $0.id?.uuidString }
        let walk = WalkModel(entries: trip == nil ? Array(entries) : split.inPlay, zones: Array(zones),
                             items: Array(items))
        VStack(spacing: 10) {
            ScreenHeader(storeName: store.displayName, title: trip == nil ? "Shopping list" : "In the store",
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
                        suggestionList
                    } else if trip == nil {
                        HomeListEditor(store: store)
                    } else {
                        inStore(walk, notHere: split.notHere)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            if trip == nil {
                TripBar(title: "Start trip", systemImage: "cart", action: startTrip) {
                    Button { showingZones = true } label: { Image(systemName: "square.stack.3d.up") }
                        .buttonStyle(.sk1Key())
                        .accessibilityLabel("Zones")
                    Button { showingEverything = true } label: { Image(systemName: "tray.full") }
                        .buttonStyle(.sk1Key())
                        .accessibilityLabel("Everything: the last trip and every item this store remembers")
                    if profile.mapsStore {
                        Button { showingFloorPlan = true } label: {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        .buttonStyle(.sk1Key())
                        .accessibilityLabel("Floor plan")
                    }
                    ShareKey(store: store)
                }
            } else {
                TripBar(title: doneTitle, systemImage: "checkmark", action: finishTrip) { EmptyView() }
            }
        }
        .padding(.top, 4)
        .sheet(item: $editing) { EditEntrySheet(entry: $0.entry, zones: Array(zones)) }
        .sheet(isPresented: $showingZones) { ZonesSheet(store: store) }
        .sheet(isPresented: $showingFloorPlan) { FloorPlanSheet(store: store) }
        .sheet(isPresented: $showingEverything) { EverythingSheet(store: store) }
        .onAppear {
            actions.endLapsedTrips()
            ZoneGuessing.guessMissing(in: store, context: context)
            applyDemoScreen()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { actions.endLapsedTrips() }
        }
    }

    private var doneTitle: String {
        let got = entries.filter { $0.isChecked && $0.checkedByID == profile.id }.count
        return "Done · \(got) got"
    }

    // MARK: In the store

    /// The trip: what the buttons do, a card per zone in walking order, then Not here.
    @ViewBuilder private func inStore(_ walk: WalkModel, notHere: [ListEntry]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(Image(systemName: "circle")) Got it  ·  Not here: keep it for next time  ·  \(Image(systemName: "trash")) Don't want it")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
            if walk.rows.isEmpty && notHere.isEmpty {
                Text("Nothing on the list. Type above to add something.")
                    .sk1Hint()
            }
            ForEach(walk.stops, id: \.id) { stop in
                zoneCard(stop)
            }
            if !notHere.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ZoneHeader(title: "Not here · next time", count: "\(notHere.count)", state: .done)
                    ListCard {
                        ForEach(Array(notHere.enumerated()), id: \.element.objectID) { index, entry in
                            ItemRow(name: entry.displayName, detail: entry.note, quantity: entry.quantity,
                                    isChecked: false, showsDivider: index > 0,
                                    accessory: AnyView(trashKey(entry)), toggle: { actions.toggle(entry) })
                        }
                    }
                    Text("These stay on your list for the next trip. Found one after all? Tap its circle.")
                        .sk1Hint()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// One zone: its heading and how many are left, and its card. Items keep their place once got, struck through.
    private func zoneCard(_ stop: Walk.Stop<ListRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZoneHeader(title: stop.state == .next ? "\(stop.title) · next" : stop.title,
                       count: stop.left == 0 ? "All got" : "\(stop.left) left", state: stop.state)
            ListCard {
                ForEach(Array(stop.entries.enumerated()), id: \.element.entry.objectID) { index, row in
                    tripRow(row, index: index)
                        .modifier(DragToMove(entry: row.entry, target: $dropTarget) { move($0, onto: row.entry) })
                }
            }
            if stop.kind == .lookForIt {
                Text("These move around the store, so they're not in a zone. Keep an eye out for them.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A row in the store: the circle (got it), Not here and the trash. Hold it to edit it.
    private func tripRow(_ row: ListRow, index: Int) -> some View {
        let entry = row.entry
        let keys = HStack(spacing: 6) {
            if !entry.isChecked {
                Button("Not here") { actions.markNotHere(entry) }
                    .buttonStyle(.sk1Key(size: .small))
                    .accessibilityLabel("\(entry.displayName) isn't here")
                    .accessibilityHint("Keeps it on the list for next time")
                trashKey(entry)
            }
        }
        return ItemRow(name: entry.displayName, detail: detail(entry, lookFor: lookFor(row)),
                       detailTone: lookFor(row) != nil ? .alert : .soft, quantity: entry.quantity,
                       isChecked: entry.isChecked, showsDivider: index > 0, accessory: AnyView(keys),
                       toggle: { actions.toggle(entry) })
            .contextMenu {
                Button("Edit", systemImage: "pencil") { editing = Editing(entry: entry) }
            }
            .accessibilityAction(named: "Edit") { editing = Editing(entry: entry) }
    }

    private func trashKey(_ entry: ListEntry) -> some View {
        Button { actions.remove(entry) } label: { Image(systemName: "trash") }
            .buttonStyle(.sk1Key(size: .small))
            .accessibilityLabel("Take \(entry.displayName) off the list")
    }

    /// Where an item under Look for it has been seen, or nil for every other row.
    private func lookFor(_ row: ListRow) -> String? {
        guard !row.isChecked, row.isWandering, let item = row.entry.item else { return nil }
        let seen = service.wanderNote(for: item) ?? "Moves around"
        if let zone = item.storeZone?.displayName { return "\(seen) · \(zone)" }
        return seen
    }

    /// The note, and on a shared list who added it or has it in their cart when that isn't you.
    private func detail(_ entry: ListEntry, lookFor: String?) -> String? {
        var parts: [String] = []
        if let lookFor { parts.append(lookFor) }
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
        // A pharmacy locker text pasted in: the pickup, with its code, at the lockers.
        if let pickup = LockerPickup.parse(name) {
            service.addLockerPickup(pickup, to: store, by: profile.shopper)
            actions.save()
            draft = ""
            return
        }
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
        let split = profile.notHere.split(Array(entries)) { $0.id?.uuidString }
        let walk = WalkModel(entries: split.inPlay, zones: Array(zones), items: Array(items))
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

    private func startTrip() {
        actions.start()
    }

    /// Done: what you got comes off the list; what wasn't here, and anything not checked off, stays for next time.
    private func finishTrip() {
        _ = actions.finish(trip)
    }

    private func applyDemoScreen() {
        guard Launch.isDemo, !appliedDemo else { return }
        appliedDemo = true
        switch Launch.demoScreen {
        case "add": draft = "chi"
        case "zones": showingZones = true
        case "floorplan": showingFloorPlan = true
        case "everything": showingEverything = true
        case "trip":
            if let pesto = entries.first(where: { $0.displayName == "Kirkland pesto" }) {
                profile.notHere.mark(pesto.id?.uuidString)
            }
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
            let main = next.map { "Next · \($0.entry.entry.displayName)" } ?? "All got · tap Done"
            let middle = nextStop?.title ?? "Checkout"
            return TripLCD(label: "In the store · \(minutes) min", main: main, number: left, unit: "left",
                           strip: strip, legend: ["Entry", middle, "Exit"])
        }
        let main = left == 0 ? "A blank list" : stopCount == 1 ? "1 zone to visit" : "\(stopCount) zones to visit"
        return TripLCD(label: "At home · \(store.displayName)", main: main, number: left, unit: "on list",
                       strip: strip, legend: ["Entry", "Sorted at Start trip", "Exit"])
    }
}
