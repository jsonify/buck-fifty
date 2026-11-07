import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// The item the editor is open on. Core Data objects aren't Identifiable here, so `sheet(item:)` gets this.
struct EditingItem: Identifiable {
    let item: Item
    var id: NSManagedObjectID { item.objectID }
}

/// Everything a store remembers, whether it's on the list or not. Opens by itself after Done, so a trip can be
/// reviewed: the last trip in the order things were checked off, then every item in walking order under its zone.
/// Tap an item to set its zone, rename it, put it back on the list or forget it; hold and drag one onto another to
/// move it in the walk. Zone guesses run here for anything without a zone, and say why when they can't.
struct EverythingSheet: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var items: FetchedResults<Item>
    @FetchRequest private var zones: FetchedResults<Zone>
    @State private var editing: EditingItem?
    @State private var dropTarget: NSManagedObjectID?

    init(store: Store) {
        self.store = store
        _items = FetchRequest(fetchRequest: Fetch.items(in: store))
        _zones = FetchRequest(fetchRequest: Fetch.zones(in: store))
    }

    private var service: ListService { ListService(context: context) }

    var body: some View {
        SheetScaffold(title: "Everything", detail: "\(items.count) REMEMBERED") {
            if items.isEmpty {
                Text("Nothing remembered yet. Everything you add to the list stays here, with its zone and where you "
                     + "grab it, even after you've bought it.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                guesses
                lastTrip
                everything
            }
        } actions: {
            Button("Guess zones") { ZoneGuessing.guessMissing(in: store, context: context) }
                .buttonStyle(.sk1Key())
                .disabled(!ZoneGuesser.status.isReady || waiting == 0 || ZoneGuessing.isRunning(for: store))
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.sk1Key(.orange))
        }
        .sheet(item: $editing) { EditItemSheet(item: $0.item, zones: Array(zones)) }
        .onAppear { ZoneGuessing.guessMissing(in: store, context: context) }
    }

    // MARK: Zone guesses

    private var waiting: Int { ZoneGuessing.waiting(in: store, context: context) }

    @ViewBuilder private var guesses: some View {
        let unzoned = items.filter { $0.storeZone == nil }.count
        if unzoned > 0 {
            SKGroup(caption: "Zones") {
                SKRow(title: unzoned == 1 ? "1 item has no zone" : "\(unzoned) items have no zone",
                      subtitle: guessNote) {
                    SKChip("\(unzoned)", minWidth: 36)
                }
            }
        }
    }

    private var guessNote: String {
        switch ZoneGuesser.status {
        case .unavailable(let why):
            return why + " Tap an item to set its zone."
        case .ready:
            if ZoneGuessing.isRunning(for: store) { return "Apple Intelligence is guessing them on this iPhone…" }
            if waiting > 0 { return "Guess zones asks Apple Intelligence, on this iPhone. Or tap an item." }
            return "Tap an item to set its zone. (Guesses never replace a zone you chose, \"No zone\" included.)"
        }
    }

    // MARK: The last trip

    @ViewBuilder private var lastTrip: some View {
        if let trip = service.lastTrip(at: store) {
            let bought = service.items(boughtOn: trip)
            SKGroup(caption: "Last trip · \(when(trip))",
                    note: "In the order they were checked off, which is what the list learns its order from.") {
                ForEach(Array(bought.enumerated()), id: \.element.objectID) { index, item in
                    RememberedRow(item: item, subtitle: "\(index + 1). \(zoneName(item))",
                                  onList: service.isOnList(item)) {
                        editing = EditingItem(item: item)
                    }
                }
            }
        }
    }

    private func when(_ trip: Trip) -> String {
        guard let ended = trip.endedAt else { return "" }
        let who = trip.shopperName.map { " · \($0)" } ?? ""
        return ended.formatted(date: .abbreviated, time: .shortened) + who
    }

    // MARK: Everything, in walking order

    /// Every remembered item, for `ListOrdering`.
    private struct Row: ListSortable {
        let item: Item
        let zoneIndex: Int?
        var sortName: String { item.displayName }
        var isChecked: Bool { false }
        var learnedPosition: Double? { item.learnedPosition?.doubleValue }
    }

    private var arrangement: (rows: [Row], zoneNames: [String], zonePositions: [Int: Double]) {
        let zoneList = Array(zones)
        let rows = items.map { Row(item: $0, zoneIndex: $0.storeZone.flatMap { zoneList.firstIndex(of: $0) }) }
        let zonePositions = ListOrdering.zoneAverages(rows.filter { !$0.item.wanders }
            .map { (zone: $0.zoneIndex, position: $0.learnedPosition) })
        return (rows, zoneList.map(\.displayName), zonePositions)
    }

    @ViewBuilder private var everything: some View {
        let a = arrangement
        let sections = ListOrdering.sections(a.rows, zoneNames: a.zoneNames, zonePositions: a.zonePositions)
        ForEach(sections, id: \.id) { section in
            SKGroup(caption: section.title) {
                ForEach(section.entries, id: \.item.objectID) { row in
                    RememberedRow(item: row.item, subtitle: detail(row.item), onList: service.isOnList(row.item)) {
                        editing = EditingItem(item: row.item)
                    }
                    .draggable(row.item.id?.uuidString ?? "") { SKChip(row.item.displayName) }
                    .dropDestination(for: String.self) { ids, _ in
                        move(ids.first, onto: row.item)
                    } isTargeted: { over in
                        if over {
                            dropTarget = row.item.objectID
                        } else if dropTarget == row.item.objectID {
                            dropTarget = nil
                        }
                    }
                    .overlay {
                        if dropTarget == row.item.objectID {
                            RoundedRectangle(cornerRadius: 6).stroke(Color(sk1Hex: SK1.orange), lineWidth: 2)
                        }
                    }
                }
            }
        }
    }

    private func zoneName(_ item: Item) -> String {
        item.storeZone?.displayName ?? "No zone yet"
    }

    /// Its zone and where in the walk it's grabbed.
    private func detail(_ item: Item) -> String {
        if item.wanders { return "\(zoneName(item)) · moves around" }
        guard let position = item.learnedPosition?.doubleValue else { return "\(zoneName(item)) · not bought yet" }
        return "\(zoneName(item)) · \(Int((position * 100).rounded()))% of the way round"
    }

    /// Moves the dragged item (by its id) to `target`'s place in the walk, and `target`'s zone if it has one.
    private func move(_ id: String?, onto target: Item) -> Bool {
        dropTarget = nil
        let a = arrangement
        let rows = ListOrdering.sorted(a.rows, zoneCount: a.zoneNames.count, zonePositions: a.zonePositions)
        guard let id, let from = rows.firstIndex(where: { $0.item.id?.uuidString == id }),
              let to = rows.firstIndex(where: { $0.item == target }), from != to else { return false }
        let item = rows[from].item
        let keys = ListOrdering.walkPositions(rows, zoneCount: a.zoneNames.count, zonePositions: a.zonePositions)
        var positions: [Item: Double] = [:]
        for (index, position) in ListOrdering.positionsAfterMove(keys, from: from, to: to) {
            positions[rows[index].item] = position
        }
        if let zone = target.storeZone, zone != item.storeZone { service.setZone(zone, for: item) }
        service.place(positions, moved: item)
        try? service.save()
        return true
    }
}

/// A remembered item: its name, a detail line, and whether it's on the list or its zone is a guess.
struct RememberedRow: View {
    @ObservedObject var item: Item
    let subtitle: String
    let onList: Bool
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            SKRow(title: item.displayName, subtitle: subtitle) {
                if item.isZoneGuessed {
                    SKChip("GUESSED", minWidth: 64)
                } else if onList {
                    SKChip("ON LIST", minWidth: 64)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit")
    }
}

/// Edit a remembered item: its name and zone, put it back on the list, or forget it.
struct EditItemSheet: View {
    @ObservedObject var item: Item
    let zones: [Zone]
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Profile.self) private var profile
    @State private var name = ""
    @State private var zone: Zone?
    @State private var nameTaken = false
    @State private var confirmingForget = false
    @State private var spot: WanderOverride?

    private var service: ListService { ListService(context: context) }

    var body: some View {
        SheetScaffold(title: "Item", detail: service.isOnList(item) ? "ON THE LIST" : "NOT ON THE LIST") {
            CaptionedField(caption: "Name",
                           note: nameTaken ? "This store already remembers an item called that." : nil) {
                SKTextField("Name", text: $name)
            }
            CaptionedField(caption: item.isZoneGuessed ? "Zone · guessed" : "Zone", note: zoneNote) {
                ZoneField(selection: $zone, zones: zones)
            }
            SpotField(selection: $spot, tripsSayWanders: item.isWandering)
            Text(positionNote).sk1Hint().fixedSize(horizontal: false, vertical: true)
        } actions: {
            Button("Forget") { confirmingForget = true }.buttonStyle(.sk1Key(.charcoal))
            Spacer()
            Button("Add to list", action: addToList)
                .buttonStyle(.sk1Key())
                .disabled(service.isOnList(item))
            Button("Save", action: save).buttonStyle(.sk1Key(.orange))
        }
        .confirmationDialog("Forget \(item.displayName)?", isPresented: $confirmingForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive, action: forget)
        } message: {
            Text("It comes off the list and out of the suggestions, and where you grab it is lost.")
        }
        .onAppear {
            name = item.displayName
            zone = item.storeZone
            spot = item.wanderChoice
        }
    }

    private var zoneNote: String {
        if item.isZoneGuessed { return "Guessed by Apple Intelligence. Save to keep it, or pick the right one." }
        return "Where it is in the store. It keeps this zone every time it's on the list."
    }

    private var positionNote: String {
        let trips = item.positionSampleCount
        if item.wanders, let seen = service.wanderNote(for: item) { return "\(seen)." }
        guard let position = item.learnedPosition?.doubleValue else {
            return "Not bought on a trip yet: once it's checked off in the store, it learns where it goes."
        }
        let percent = Int((position * 100).rounded())
        let taught = trips == 1 ? "1 trip" : "\(trips) trips"
        return "Grabbed about \(percent)% of the way round the store (learned from \(taught))."
    }

    /// Applies the name and zone. Returns false (and says so) when the name belongs to another item.
    private func apply() -> Bool {
        if ItemName.cleaned(name) != item.displayName, !service.renameItem(item, to: name) {
            nameTaken = !ItemName.cleaned(name).isEmpty
            if nameTaken { return false }
        }
        // Changing the zone sets it by hand; saving a guessed one unchanged confirms it.
        if item.storeZone != zone {
            service.setZone(zone, for: item)
        } else {
            service.confirmZone(of: item)
        }
        service.setWanderOverride(spot, for: item)
        return true
    }

    private func save() {
        guard apply() else { return }
        try? service.save()
        dismiss()
    }

    private func addToList() {
        guard apply(), let store = item.store else { return }
        service.addToList(item.displayName, store: store, by: profile.shopper)
        try? service.save()
        dismiss()
    }

    private func forget() {
        service.forget(item)
        try? service.save()
        dismiss()
    }
}
