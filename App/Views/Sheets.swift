import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// Edit one entry: its name, zone, how many and a note. The zone belongs to the item, so it sticks next time.
struct EditEntrySheet: View {
    @ObservedObject var entry: ListEntry
    let zones: [Zone]
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var zone: Zone?
    @State private var quantity: Int64 = 1
    @State private var note = ""
    @State private var spot: WanderOverride?

    var body: some View {
        SheetScaffold(title: "Edit item", detail: entry.addedByName.map { "ADDED BY \($0.uppercased())" } ?? "") {
            CaptionedField(caption: "Name") {
                SKTextField("Name", text: $name)
            }
            CaptionedField(caption: entry.item?.isZoneGuessed == true ? "Zone · guessed" : "Zone", note: zoneNote) {
                ZoneField(selection: $zone, zones: zones)
            }
            SpotField(selection: $spot, tripsSayWanders: entry.item?.isWandering == true)
            CaptionedField(caption: "How many") {
                SKPicker(selection: $quantity, options: quantityOptions)
            }
            CaptionedField(caption: "Note") {
                SKTextField("Note", text: $note, prompt: "The dark roast, the big one…")
            }
        } actions: {
            Button("Remove") { remove() }.buttonStyle(.sk1Key(.charcoal))
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(.sk1Key())
            Button("Save", action: save).buttonStyle(.sk1Key(.orange))
        }
        .onAppear {
            name = entry.displayName
            zone = entry.item?.storeZone
            quantity = max(entry.quantity, 1)
            note = entry.note ?? ""
            spot = entry.item?.wanderChoice
        }
    }

    private var zoneNote: String {
        if entry.item?.isZoneGuessed == true {
            return "Guessed on this iPhone by Apple Intelligence. Save to keep it, or pick the right one."
        }
        return "Where it is in the store. It keeps this zone every time it's on the list."
    }

    private var quantityOptions: [SKPicker<Int64>.Option] {
        (1...24).map { SKPicker<Int64>.Option(Int64($0), "\($0)") }
    }

    private func save() {
        let service = ListService(context: context)
        if let item = service.rename(entry, to: name) {
            // Changing the zone sets it by hand; saving a guessed one unchanged confirms it.
            if item.storeZone != zone {
                service.setZone(zone, for: item)
            } else {
                service.confirmZone(of: item)
            }
            service.setWanderOverride(spot, for: item)
        }
        entry.quantity = quantity
        let cleanedNote = ItemName.cleaned(note)
        entry.note = cleanedNote.isEmpty ? nil : cleanedNote
        try? service.save()
        dismiss()
    }

    private func remove() {
        let service = ListService(context: context)
        service.remove(entry)
        try? service.save()
        dismiss()
    }
}

/// The store's zones in walking order: front door at the top, checkout at the bottom.
struct ZonesSheet: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(Profile.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var zones: FetchedResults<Zone>
    @State private var newZone = ""
    /// The zone a dragged zone is over: it will take that zone's place.
    @State private var dropTarget: NSManagedObjectID?
    /// The layout waiting for "Replace zones?" to be confirmed.
    @State private var pendingLayout: ZoneLayout?

    init(store: Store) {
        self.store = store
        _zones = FetchRequest(fetchRequest: Fetch.zones(in: store))
    }

    var body: some View {
        SheetScaffold(title: "Zones", detail: "\(zones.count) IN WALKING ORDER") {
            if zones.isEmpty {
                Text("No zones yet. Add the parts of the store in the order you walk through them.").sk1Hint()
            } else {
                SKGroup(caption: "Walking order",
                        note: "Front door at the top, checkout at the bottom. Hold a zone and drag it to move it.") {
                    ForEach(Array(zones.enumerated()), id: \.element.objectID) { index, zone in
                        SKRow(title: zone.displayName, subtitle: itemCount(zone)) {
                            HStack(spacing: 4) {
                                Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                                    .buttonStyle(.sk1Key(.round, size: .small))
                                    .disabled(index == 0)
                                    .accessibilityLabel("Move \(zone.displayName) up")
                                Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                                    .buttonStyle(.sk1Key(.round, size: .small))
                                    .disabled(index == zones.count - 1)
                                    .accessibilityLabel("Move \(zone.displayName) down")
                                Button { delete(zone) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.sk1Key(.round, size: .small))
                                    .accessibilityLabel("Delete \(zone.displayName)")
                            }
                        }
                        .contentShape(Rectangle())
                        .draggable(zone.id?.uuidString ?? "") { SKChip(zone.displayName) }
                        .dropDestination(for: String.self) { ids, _ in
                            drop(ids.first, at: index)
                        } isTargeted: { over in
                            if over {
                                dropTarget = zone.objectID
                            } else if dropTarget == zone.objectID {
                                dropTarget = nil
                            }
                        }
                        .overlay {
                            if dropTarget == zone.objectID {
                                RoundedRectangle(cornerRadius: 6).stroke(Color(sk1Hex: SK1.orange), lineWidth: 2)
                            }
                        }
                    }
                }
            }
            SKGroup(caption: "Start from a layout",
                    note: "Replaces these zones in one go. Zones with the same name keep their items.") {
                ForEach(DefaultZones.layouts, id: \.self) { layout in
                    Button { pendingLayout = layout } label: {
                        SKRow(title: layout.name, subtitle: "\(layout.zones.count) zones · \(layout.detail)") {
                            SKChip(layout.matches(zones.map(\.displayName)) ? "IN USE" : "USE", minWidth: 64)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(layout.matches(zones.map(\.displayName)))
                }
            }
            CaptionedField(caption: "Add a zone", note: "New zones go at the end; move them into place.") {
                HStack(spacing: 6) {
                    SKTextField("Zone name", text: $newZone, prompt: "Pharmacy")
                        .onSubmit(addZone)
                    Button(action: addZone) { Image(systemName: "plus") }
                        .buttonStyle(.sk1Key())
                        .accessibilityLabel("Add zone")
                        .disabled(ItemName.cleaned(newZone).isEmpty)
                }
            }
        } actions: {
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.sk1Key(.orange))
        }
        .confirmationDialog("Replace the zones with \(pendingLayout?.name ?? "")?",
                            isPresented: Binding(get: { pendingLayout != nil }, set: { if !$0 { pendingLayout = nil } }),
                            titleVisibility: .visible) {
            Button("Replace zones", role: .destructive) {
                if let layout = pendingLayout { apply(layout) }
            }
        } message: {
            Text(replaceMessage)
        }
    }

    private var replaceMessage: String {
        guard let layout = pendingLayout else { return "" }
        let keys = Set(layout.zones.map(ItemName.normalized))
        let losing = zones.filter { !keys.contains(ItemName.normalized($0.displayName)) }
            .reduce(0) { $0 + ($1.items?.count ?? 0) }
        let note = losing == 0 ? "" : " \(losing == 1 ? "1 item loses its zone" : "\(losing) items lose their zones") "
            + "and can be guessed again."
        return "\(layout.zones.count) zones in walking order.\(note) What you've learned about the order is kept."
    }

    private func apply(_ layout: ZoneLayout) {
        let service = ListService(context: context)
        service.replaceZones(of: store, with: layout.zones)
        try? service.save()
        pendingLayout = nil
        profile.markTried(Milestones.Try.layout)
        ZoneGuessing.guessMissing(in: store, context: context)
    }

    private func itemCount(_ zone: Zone) -> String {
        let n = zone.items?.count ?? 0
        return n == 0 ? "No items yet" : n == 1 ? "1 item" : "\(n) items"
    }

    private func move(_ index: Int, by offset: Int) {
        let service = ListService(context: context)
        service.moveZone(in: store, from: index, to: index + offset)
        try? service.save()
    }

    /// Moves the dragged zone (by its id) to `index` in the walking order.
    private func drop(_ id: String?, at index: Int) -> Bool {
        dropTarget = nil
        guard let id, let from = zones.firstIndex(where: { $0.id?.uuidString == id }), from != index else {
            return false
        }
        let service = ListService(context: context)
        service.moveZone(in: store, from: from, to: index)
        try? service.save()
        return true
    }

    private func delete(_ zone: Zone) {
        let service = ListService(context: context)
        service.deleteZone(zone)
        try? service.save()
    }

    private func addZone() {
        guard !ItemName.cleaned(newZone).isEmpty else { return }
        let service = ListService(context: context)
        service.addZone(named: newZone, to: store)
        try? service.save()
        newZone = ""
    }
}
