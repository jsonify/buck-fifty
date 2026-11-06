import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// A row of the list, with its zone's place in the walk, for `ListOrdering`.
struct ListRow: ListSortable {
    let entry: ListEntry
    let zoneIndex: Int?
    var sortName: String { entry.displayName }
    var isChecked: Bool { entry.isChecked }
}

/// One store's list (the main window recipe): the LCD saying what's going on, the trays of keys, the add field, then
/// the list in zone trays in walking order, with what's in the cart at the bottom.
struct ListScreen: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Profile.self) private var profile
    @FetchRequest private var entries: FetchedResults<ListEntry>
    @FetchRequest private var zones: FetchedResults<Zone>
    @FetchRequest private var items: FetchedResults<Item>
    @FetchRequest private var openTrips: FetchedResults<Trip>
    @State private var draft = ""
    @State private var editing: ListEntry?
    @State private var showingZones = false
    @State private var appliedDemo = false

    init(store: Store) {
        self.store = store
        _entries = FetchRequest(fetchRequest: Fetch.entries(in: store))
        _zones = FetchRequest(fetchRequest: Fetch.zones(in: store))
        _items = FetchRequest(fetchRequest: Fetch.items(in: store))
        _openTrips = FetchRequest(fetchRequest: Fetch.openTrips(in: store))
    }

    private var service: ListService { ListService(context: context) }
    private var trip: Trip? { service.activeTrip(among: Array(openTrips), for: profile.shopper) }

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
        .sheet(item: $editing) { EditEntrySheet(entry: $0, zones: Array(zones)) }
        .sheet(isPresented: $showingZones) { ZonesSheet(store: store) }
        .onAppear {
            endLapsedTrips()
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
                         detail: store.displayName.uppercased(),
                         message: message(left: left),
                         number: left, digits: 3, unit: "LEFT", live: trip != nil)
    }

    private func message(left: Int) -> String {
        if let trip {
            let inCart = entries.filter { $0.isChecked && $0.checkedByID == profile.id }.count
            let since = (trip.startedAt ?? Date()).formatted(date: .omitted, time: .shortened)
            return "\(inCart) in cart · since \(since)"
        }
        if entries.isEmpty { return "List is empty" }
        if left == 0 { return "All in the cart" }
        return "Tap Start trip at the door"
    }

    private var keys: some View {
        HStack(alignment: .top) {
            SKKeyTray(caption: "List") {
                Button { showingZones = true } label: { Image(systemName: "square.stack.3d.up") }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("Zones")
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

    @ViewBuilder private var list: some View {
        let zoneList = Array(zones)
        let rows = entries.map { entry in
            ListRow(entry: entry, zoneIndex: entry.item?.storeZone.flatMap { zoneList.firstIndex(of: $0) })
        }
        let sections = ListOrdering.sections(rows, zoneNames: zoneList.map(\.displayName))
        if sections.isEmpty {
            Text("Nothing on the list. Type above to add something; things you've bought before come back as you type.")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(sections, id: \.kind) { section in
            SKGroup(caption: section.title) {
                ForEach(section.entries, id: \.entry.objectID) { row in
                    EntryRow(entry: row.entry,
                             toggle: { toggle(row.entry) },
                             edit: { editing = row.entry },
                             remove: { remove(row.entry) })
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
    }

    private func toggle(_ entry: ListEntry) {
        service.setChecked(entry, !entry.isChecked, by: profile.shopper)
        save()
    }

    private func remove(_ entry: ListEntry) {
        service.remove(entry)
        save()
    }

    private func toggleTrip() {
        if trip == nil {
            service.startTrip(at: store, for: profile.shopper)
        } else {
            service.finishTrip(at: store, for: profile.shopper)
        }
        save()
    }

    private func endLapsedTrips() {
        _ = service.currentTrip(at: store, for: profile.shopper)
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
        case "edit": editing = entries.first { $0.displayName == "Coffee beans" }
        default: break
        }
    }
}

/// One entry: the check square, the name (and its note), and how many.
struct EntryRow: View {
    @ObservedObject var entry: ListEntry
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
                if let note = entry.note, !note.isEmpty {
                    Text(note).sk1Hint()
                }
            }
            Spacer(minLength: 8)
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
}
