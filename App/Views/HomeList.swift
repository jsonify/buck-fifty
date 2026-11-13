import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// The list before the trip, on Home and the List tab: Select from inventory over it (and Clear, which empties the list
/// after asking), then one card in your own order (`HomeOrder`). No check marks: at home you only build the list. Tap a
/// row to edit it, the trash takes it off, and holding one and dragging it onto another moves it there. Nothing here
/// starts a trip; Start trip does, in the store.
struct HomeListEditor: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(Profile.self) private var profile
    @Environment(SharingModel.self) private var sharing
    @FetchRequest private var entries: FetchedResults<ListEntry>
    @FetchRequest private var zones: FetchedResults<Zone>
    @State private var editing: Editing?
    @State private var showingInventory = false
    @State private var dropTarget: NSManagedObjectID?
    @State private var confirmingClear = false

    init(store: Store) {
        self.store = store
        _entries = FetchRequest(fetchRequest: Fetch.entries(in: store))
        _zones = FetchRequest(fetchRequest: Fetch.zones(in: store))
    }

    private var service: ListService { ListService(context: context) }
    private var actions: TripActions { TripActions(store: store, context: context, profile: profile) }

    var body: some View {
        let list = HomeOrder.sorted(Array(entries))
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { showingInventory = true } label: {
                    Label("Select from inventory", systemImage: "checklist")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.sk1Key())
                .accessibilityHint("Everything you've bought here before: tap the things you need, then Add to list")
                if !list.isEmpty {
                    Button { confirmingClear = true } label: {
                        Label("Clear", systemImage: "xmark.bin")
                    }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("Clear the list")
                    .accessibilityHint("Takes everything off the list; it all stays in the inventory")
                }
            }
            if list.isEmpty {
                Text("A blank list. Tap Select from inventory and pick what you need, or type above to add something "
                     + "new.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ZoneHeader(title: "Your list", count: list.count == 1 ? "1 thing" : "\(list.count) things")
                    ListCard {
                        ForEach(Array(list.enumerated()), id: \.element.objectID) { index, entry in
                            row(entry, index: index)
                                .modifier(DragToMove(entry: entry, target: $dropTarget) { move($0, onto: entry, in: list) })
                        }
                    }
                    Text("Tap a thing to change it; hold and drag to reorder. In the store, tap Start trip: the list "
                         + "sorts itself into the order you walk it.")
                        .sk1Hint()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(item: $editing) { EditEntrySheet(entry: $0.entry, zones: Array(zones)) }
        .sheet(isPresented: $showingInventory) { PastItemsSheet(store: store) }
        .confirmationDialog(clearTitle(list.count), isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear the list", role: .destructive, action: clear)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything you've bought before stays in the inventory, to pick again.")
        }
        .onAppear {
            guard Launch.isDemo, Launch.demoScreen == "past", !showingInventory else { return }
            showingInventory = true
        }
    }

    private func row(_ entry: ListEntry, index: Int) -> some View {
        ItemRow(name: entry.displayName, detail: detail(entry), quantity: entry.quantity, isChecked: entry.isChecked,
                showsDivider: index > 0, accessory: AnyView(trashKey(entry)))
            .onTapGesture { editing = Editing(entry: entry) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edits it")
    }

    private func trashKey(_ entry: ListEntry) -> some View {
        Button { actions.remove(entry) } label: { Image(systemName: "trash") }
            .buttonStyle(.sk1Key(size: .small))
            .accessibilityLabel("Take \(entry.displayName) off the list")
    }

    /// The note, that the last trip didn't find it, and on a shared list who added it (or has it in their cart).
    private func detail(_ entry: ListEntry) -> String? {
        var parts: [String] = []
        if profile.notHere.contains(entry.id?.uuidString) { parts.append("Not there last trip") }
        if let note = entry.note, !note.isEmpty { parts.append(note) }
        if sharing.summary(for: store).isShared {
            if entry.isChecked, let id = entry.checkedByID, id != profile.id, let name = entry.checkedByName {
                parts.append("In \(name)'s cart")
            } else if let id = entry.addedByID, id != profile.id, let name = entry.addedByName {
                parts.append("Added by \(name)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func clearTitle(_ count: Int) -> String {
        count == 1 ? "Take the 1 thing off the list?" : "Take all \(count) things off the list?"
    }

    /// Clear: everything not already in someone's cart comes off the list. The items stay remembered.
    private func clear() {
        service.dropLeftovers(in: store)
        actions.save()
    }

    /// Moves the dragged entry (by its id) to `target`'s place in your own order.
    private func move(_ id: String?, onto target: ListEntry, in list: [ListEntry]) -> Bool {
        dropTarget = nil
        guard let id, let from = list.firstIndex(where: { $0.id?.uuidString == id }),
              let to = list.firstIndex(of: target), from != to else { return false }
        service.moveAtHome(list, from: from, to: to)
        actions.save()
        profile.markTried(Milestones.Try.drag)
        return true
    }
}

/// A row that can be held and dragged onto another (`drop` gets the dragged entry's id), outlined in orange while
/// something is over it.
struct DragToMove: ViewModifier {
    let entry: ListEntry
    @Binding var target: NSManagedObjectID?
    let drop: (String?) -> Bool

    func body(content: Content) -> some View {
        content
            .draggable(entry.id?.uuidString ?? "") { SKChip(entry.displayName) }
            .dropDestination(for: String.self) { ids, _ in
                drop(ids.first)
            } isTargeted: { over in
                if over {
                    target = entry.objectID
                } else if target == entry.objectID {
                    target = nil
                }
            }
            .overlay {
                if target == entry.objectID {
                    RoundedRectangle(cornerRadius: 6).stroke(Hybrid.orange, lineWidth: 2)
                }
            }
    }
}
