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

    var body: some View {
        SheetScaffold(title: "Edit item", detail: entry.addedByName.map { "ADDED BY \($0.uppercased())" } ?? "") {
            CaptionedField(caption: "Name") {
                SKTextField("Name", text: $name)
            }
            CaptionedField(caption: entry.item?.isZoneGuessed == true ? "Zone · guessed" : "Zone", note: zoneNote) {
                SKPicker(selection: $zone, options: zoneOptions)
            }
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
        }
    }

    private var zoneNote: String {
        if entry.item?.isZoneGuessed == true {
            return "Guessed on this iPhone by Apple Intelligence. Save to keep it, or pick the right one."
        }
        return "Where it is in the store. It keeps this zone every time it's on the list."
    }

    private var zoneOptions: [SKPicker<Zone?>.Option] {
        [SKPicker<Zone?>.Option(nil, "No zone")] + zones.map { SKPicker<Zone?>.Option($0, $0.displayName) }
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
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var zones: FetchedResults<Zone>
    @State private var newZone = ""
    /// The zone a dragged zone is over: it will take that zone's place.
    @State private var dropTarget: NSManagedObjectID?

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
