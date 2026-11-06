import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// A row of the list, with its zone's place in the walk and where trips found it, for `ListOrdering`.
struct ListRow: ListSortable {
    let entry: ListEntry
    let zoneIndex: Int?
    var learnedPosition: Double? { entry.item?.learnedPosition?.doubleValue }
    var sortName: String { entry.displayName }
    var isChecked: Bool { entry.isChecked }
}

/// The entry the edit sheet is open on. Core Data objects aren't Identifiable here, so `sheet(item:)` gets this.
struct Editing: Identifiable {
    let entry: ListEntry
    var id: NSManagedObjectID { entry.objectID }
}

/// One store's list (the main window recipe): the LCD saying what's going on, the trays of keys, the add field, then
/// the list in zone trays in the order the store is walked (learned from check-offs), with what's in the cart at the
/// bottom.
struct ListScreen: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Profile.self) private var profile
    @Environment(SharingModel.self) private var sharing
    @FetchRequest private var entries: FetchedResults<ListEntry>
    @FetchRequest private var zones: FetchedResults<Zone>
    @FetchRequest private var items: FetchedResults<Item>
    @FetchRequest private var openTrips: FetchedResults<Trip>
    @State private var draft = ""
    @State private var editing: Editing?
    @State private var showingZones = false
    @State private var showingMap = false
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
    private var mapper: StoreMapper { StoreMapper.shared }
    private var trip: Trip? { service.activeTrip(among: Array(openTrips), for: profile.shopper) }
    private var share: ShareSummary { sharing.summary(for: store) }
    /// Other people's trips at this store that are still going: they're in the store now.
    private var othersShopping: [String] {
        openTrips.filter { other in
            other.shopperID != profile.id
                && service.activeTrip(among: [other], for: Shopper(id: other.shopperID ?? "", name: "")) != nil
        }
        .compactMap(\.shopperName)
    }

    var body: some View {
        VStack(spacing: 10) {
            display
            keys
            addBar
            SKGroove()
            ScrollView {
                VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                    if draftIsBlank {
                        list
                    } else {
                        suggestionList
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .sk1Chassis()
        .navigationTitle(store.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { EditEntrySheet(entry: $0.entry, zones: Array(zones)) }
        .sheet(isPresented: $showingZones) { ZonesSheet(store: store) }
        .sheet(isPresented: $showingMap) { FloorPlanSheet(store: store) }
        .sheet(isPresented: $showingEverything) { EverythingSheet(store: store) }
        .onAppear {
            endLapsedTrips()
            ZoneGuessing.guessMissing(in: store, context: context)
            applyDemoScreen()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { endLapsedTrips() }
        }
    }

    // MARK: The LCD and keys

    private var display: some View {
        let left = entries.filter { !$0.isChecked }.count
        return SKDisplay(title: trip == nil ? "At home" : "In the store",
                         detail: detail,
                         message: message(left: left),
                         number: left, digits: 3, unit: "LEFT", live: trip != nil)
    }

    /// The line under the title: who else is in the store, who the list is shared with, or the store's name.
    private var detail: String {
        if let other = othersShopping.first { return "\(other.uppercased()) IN STORE" }
        if share.isShared { return "SHARED · \(share.people.uppercased())" }
        return store.displayName.uppercased()
    }

    /// The LCD's middle column: a few characters fit, so short status only.
    private func message(left: Int) -> String {
        if trip != nil {
            let inCart = entries.filter { $0.isChecked && $0.checkedByID == profile.id }.count
            return "\(inCart) in cart"
        }
        if entries.isEmpty { return "Empty" }
        if left == 0 { return "All in" }
        return "Ready"
    }

    private var keys: some View {
        HStack(alignment: .top) {
            SKKeyTray(caption: "List") {
                Button { showingZones = true } label: { Image(systemName: "square.stack.3d.up") }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("Zones")
                Button { showingEverything = true } label: { Image(systemName: "tray.full") }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("Everything: the last trip and every item this store remembers")
                if profile.mapsStore {
                    Button { showingMap = true } label: { Image(systemName: "map") }
                        .buttonStyle(.sk1Key(isOn: mapper.isRecording(trip)))
                        .accessibilityLabel(mapper.isRecording(trip) ? "Floor plan, mapping this trip" : "Floor plan")
                }
                Button {
                    Task { await sharing.presentSharing(for: store) }
                } label: {
                    Image(systemName: share.isShared ? "person.2.fill" : "person.badge.plus")
                }
                .buttonStyle(.sk1Key(isOn: share.isShared))
                .disabled(sharing.isWorking)
                .accessibilityLabel(share.isShared ? "Shared with \(share.people)" : "Share this list")
            }
            Spacer()
            SKKeyTray(caption: "Trip") {
                Button(trip == nil ? "Start trip" : "Done", action: toggleTrip)
                    .buttonStyle(.sk1Key(.orange))
            }
        }
    }

    private var addBar: some View {
        HStack(spacing: 6) {
            SKTextField("Add an item", text: $draft, prompt: "Add to \(store.displayName)…")
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit { add(draft) }
            Button { add(draft) } label: { Image(systemName: "plus") }
                .buttonStyle(.sk1Key())
                .accessibilityLabel("Add")
                .disabled(draftIsBlank)
        }
    }

    // MARK: The list

    private var draftIsBlank: Bool { ItemName.cleaned(draft).isEmpty }

    /// The list's rows with what ordering them needs.
    private struct Arrangement {
        let rows: [ListRow]
        let zoneNames: [String]
        let zonePositions: [Int: Double]

        var sections: [ListSection<ListRow>] {
            ListOrdering.sections(rows, zoneNames: zoneNames, zonePositions: zonePositions)
        }

        /// The rows still to get, in list order.
        var unchecked: [ListRow] {
            ListOrdering.sorted(rows, zoneCount: zoneNames.count, zonePositions: zonePositions).filter { !$0.isChecked }
        }
    }

    private var arrangement: Arrangement {
        let zoneList = Array(zones)
        let rows = entries.map { entry in
            ListRow(entry: entry, zoneIndex: entry.item?.storeZone.flatMap { zoneList.firstIndex(of: $0) })
        }
        let zonePositions = ListOrdering.zoneAverages(items.map { item in
            (zone: item.storeZone.flatMap { zoneList.firstIndex(of: $0) }, position: item.learnedPosition?.doubleValue)
        })
        return Arrangement(rows: rows, zoneNames: zoneList.map(\.displayName), zonePositions: zonePositions)
    }

    @ViewBuilder private var list: some View {
        let sections = arrangement.sections
        if sections.isEmpty {
            Text("Nothing on the list. Type above to add something; things you've bought before come back as you type.")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(sections, id: \.id) { section in
            SKGroup(caption: section.title) {
                ForEach(section.entries, id: \.entry.objectID) { row in
                    EntryRow(entry: row.entry, me: profile.id, showsWho: share.isShared,
                             guessedZone: row.entry.item?.isZoneGuessed == true,
                             toggle: { toggle(row.entry) },
                             edit: { editing = Editing(entry: row.entry) },
                             remove: { remove(row.entry) })
                    // Hold and drag an item onto another to move it to that place in the walk (and that zone).
                    .draggable(row.entry.id?.uuidString ?? "") { SKChip(row.entry.displayName) }
                    .dropDestination(for: String.self) { ids, _ in
                        move(ids.first, onto: row.entry)
                    } isTargeted: { over in
                        if over {
                            dropTarget = row.entry.objectID
                        } else if dropTarget == row.entry.objectID {
                            dropTarget = nil
                        }
                    }
                    .overlay {
                        if dropTarget == row.entry.objectID {
                            RoundedRectangle(cornerRadius: 6).stroke(Color(sk1Hex: SK1.orange), lineWidth: 2)
                        }
                    }
                }
            }
        }
    }

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
        save()
        draft = ""
        // The zone is guessed in the background: adding never waits for it.
        ZoneGuessing.guessMissing(in: store, context: context)
    }

    /// Moves the dragged entry (by its id) to `target`'s place in the list: it gets a position between its new
    /// neighbours, and `target`'s zone if it has one.
    private func move(_ id: String?, onto target: ListEntry) -> Bool {
        dropTarget = nil
        let arrangement = self.arrangement
        let rows = arrangement.unchecked
        guard let id, let from = rows.firstIndex(where: { $0.entry.id?.uuidString == id }),
              let to = rows.firstIndex(where: { $0.entry == target }), from != to,
              let item = rows[from].entry.item else { return false }
        let keys = ListOrdering.walkPositions(rows, zoneCount: arrangement.zoneNames.count,
                                              zonePositions: arrangement.zonePositions)
        var positions: [Item: Double] = [:]
        for (index, position) in ListOrdering.positionsAfterMove(keys, from: from, to: to) {
            if let moved = rows[index].entry.item { positions[moved] = position }
        }
        if let zone = target.item?.storeZone, zone != item.storeZone { service.setZone(zone, for: item) }
        service.place(positions, moved: item)
        save()
        return true
    }

    private func toggle(_ entry: ListEntry) {
        let checkOff = service.setChecked(entry, !entry.isChecked, by: profile.shopper)
        if let checkOff, let item = entry.item, mapper.isRecording(checkOff.trip) {
            service.setPoint(mapper.mark(checkOff, landmark: service.landmark(of: item)), of: checkOff)
        }
        save()
    }

    private func remove(_ entry: ListEntry) {
        service.remove(entry)
        save()
    }

    private func toggleTrip() {
        if trip == nil {
            let started = service.startTrip(at: store, for: profile.shopper)
            // Start trip is "start at the door": the origin of the map.
            if profile.mapsStore, StoreMapper.isAvailable, !Launch.isDemo {
                mapper.start(started, gridHeading: store.gridHeading?.doubleValue)
            }
        } else {
            let bought = trip.map { service.route(of: $0).count } ?? 0
            if let trip, mapper.isRecording(trip) { finishMapping(trip, atCheckout: true) }
            service.finishTrip(at: store, for: profile.shopper)
            save()
            // What you bought comes off the list; the trip's review is where to set zones and fix the order.
            if bought > 0 { showingEverything = true }
            return
        }
        save()
    }

    /// Saves the mapped walk of `trip`. At the checkout (Done), the walk's end is pinned to the store's checkout.
    private func finishMapping(_ trip: Trip, atCheckout: Bool) {
        let result = mapper.finish(checkout: atCheckout ? service.checkoutSpot(in: store) : nil)
        service.recordPath(result.path, points: result.points, of: trip)
        if store.gridHeading == nil, let grid = result.gridHeading { store.gridHeading = NSNumber(value: grid) }
    }

    private func endLapsedTrips() {
        _ = service.currentTrip(at: store, for: profile.shopper)
        // A mapped trip that went quiet ended away from the checkout: keep its walk, uncorrected at the end.
        if let mapped = mapper.trip, mapped.endedAt != nil, mapped.store == store {
            finishMapping(mapped, atCheckout: false)
        }
        save()
    }

    private func save() {
        do {
            try service.save()
        } catch {
            context.rollback()
            print("Buck Fifty: save failed: \(error)")
        }
    }

    private func applyDemoScreen() {
        guard Launch.isDemo, !appliedDemo else { return }
        appliedDemo = true
        switch Launch.demoScreen {
        case "add": draft = "chi"
        case "zones": showingZones = true
        case "map": showingMap = true
        case "everything": showingEverything = true
        case "edit", "zone": editing = entries.first { $0.displayName == "Coffee beans" }.map(Editing.init)
        default: break
        }
    }
}

/// One entry: the check square, the name (and its note), and how many.
struct EntryRow: View {
    @ObservedObject var entry: ListEntry
    /// This phone's shopper id: what someone else added or checked off says who.
    let me: String
    /// Whether to say who (on a shared list).
    let showsWho: Bool
    /// Whether the item's zone is the on-device model's guess (shown as a chip that opens the editor).
    let guessedZone: Bool
    let toggle: () -> Void
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { entry.isChecked }, set: { _ in toggle() })) { EmptyView() }
                .toggleStyle(.sk1Square)
                .accessibilityLabel(Text(entry.displayName))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.sk1(SK1.TypeScale.rowTitle))
                    .strikethrough(entry.isChecked)
                    .sk1Ink(soft: entry.isChecked)
                if let detail {
                    Text(detail).sk1Hint()
                }
            }
            Spacer(minLength: 8)
            if guessedZone {
                Button(action: edit) { SKChip("GUESSED", minWidth: 64) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Zone guessed: \(entry.item?.storeZone?.displayName ?? ""). Edit")
            }
            if entry.quantity > 1 {
                SKChip("×\(entry.quantity)", minWidth: 32)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: edit)
            Button("Remove from list", systemImage: "trash", role: .destructive, action: remove)
        }
        .accessibilityAction(named: "Edit", edit)
    }

    /// The note, and on a shared list who added it or has it in their cart when that isn't you.
    private var detail: String? {
        var parts: [String] = []
        if let note = entry.note, !note.isEmpty { parts.append(note) }
        if showsWho {
            if entry.isChecked, let id = entry.checkedByID, id != me, let name = entry.checkedByName {
                parts.append("In \(name)'s cart")
            } else if !entry.isChecked, let id = entry.addedByID, id != me, let name = entry.addedByName {
                parts.append("Added by \(name)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
