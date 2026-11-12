import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// The inventory (Select from inventory, over the list at home): everything the store remembers, so a blank list can
/// be built in a few taps. Usual (what you buy most, most first), Running low (what Restock says runs out before the
/// next trip), Last trip, or everything A to Z; the find field narrows it. Tap the things you need to pick them (tap
/// again to unpick), then Add to list puts them all on the list at once. What's already on the list says so.
struct PastItemsSheet: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Profile.self) private var profile
    @FetchRequest private var items: FetchedResults<Item>
    @FetchRequest private var entries: FetchedResults<ListEntry>
    @State private var query = ""
    @State private var filter: PastItemsFilter = .usual
    /// What's picked, to add with Add to list.
    @State private var picked: Set<NSManagedObjectID> = []

    init(store: Store) {
        self.store = store
        _items = FetchRequest(fetchRequest: Fetch.items(in: store))
        _entries = FetchRequest(fetchRequest: Fetch.entries(in: store))
    }

    private var service: ListService { ListService(context: context) }

    private typealias Choice = SKSegmented<PastItemsFilter>.Option

    var body: some View {
        let now = Date()
        let all = service.pastItems(in: store, now: now)
        let shown = PastItems.filtered(all, by: filter, query: query)
        let bought = all.filter { $0.timesBought > 0 }.count
        SheetScaffold(title: "Inventory", detail: "\(bought) BOUGHT BEFORE") {
            SKTextField("Find", text: $query, prompt: "Find something you've bought…")
                .textInputAutocapitalization(.never)
            SKSegmented(selection: $filter, options: [
                Choice(.usual, "Usual", help: "What you buy most, most first"),
                Choice(.runningLow, "Low", help: "Running low before the next trip"),
                Choice(.lastTrip, "Last trip", help: "What the last trip bought"),
                Choice(.alphabetical, "A to Z", help: "Everything the store remembers"),
            ], height: 30)
            if shown.isEmpty {
                Text(emptyNote)
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SKGroup(caption: caption(shown.count),
                        note: "Tap everything you need, then Add to list. Tap again to unpick.") {
                    ForEach(shown, id: \.ref.objectID) { past in
                        let isPicked = picked.contains(past.ref.objectID)
                        Button { pick(past.ref) } label: {
                            SKRow(title: past.name, subtitle: subtitle(past, now: now)) {
                                if past.isOnList {
                                    SKChip("ON LIST", minWidth: 64)
                                } else {
                                    CheckCircle(isOn: isPicked)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(past.isOnList)
                        .accessibilityLabel(past.isOnList ? "\(past.name), already on the list" : past.name)
                        .accessibilityAddTraits(isPicked ? [.isSelected] : [])
                        .accessibilityHint(past.isOnList ? "" : isPicked ? "Unpicks it" : "Picks it to add")
                    }
                }
            }
        } actions: {
            Button("Cancel") { dismiss() }.buttonStyle(.sk1Key())
            Spacer()
            Button(picked.isEmpty ? "Add to list" : "Add \(picked.count) to list", action: addPicked)
                .buttonStyle(.sk1Key(.orange))
                .disabled(picked.isEmpty)
        }
        .onAppear(perform: pickForDemo)
    }

    private func caption(_ count: Int) -> String {
        switch filter {
        case .usual: return "What you buy most · \(count)"
        case .runningLow: return "Running low · \(count)"
        case .lastTrip: return "Last trip · \(count)"
        case .alphabetical: return "A to Z · \(count)"
        }
    }

    private var emptyNote: String {
        if !ItemName.cleaned(query).isEmpty { return "Nothing here by that name. Type it on the list to add it." }
        switch filter {
        case .usual, .alphabetical:
            return "Nothing bought here yet. Everything you check off in the store turns up here, to tap onto your "
                + "next list."
        case .runningLow: return "Nothing's running low before the next trip."
        case .lastTrip: return "No trip here yet."
        }
    }

    private func subtitle(_ past: PastItem<Item>, now: Date) -> String {
        let summary = PastItems.summary(past, now: now)
        return past.isRunningLow ? "Running low · \(summary)" : summary
    }

    private func pick(_ item: Item) {
        if picked.contains(item.objectID) {
            picked.remove(item.objectID)
        } else {
            picked.insert(item.objectID)
        }
    }

    /// Puts everything picked on the list, at the bottom of your order, and closes.
    private func addPicked() {
        for item in items where picked.contains(item.objectID) && !service.isOnList(item) {
            service.toggleOnList(item, by: profile.shopper)
        }
        try? service.save()
        ZoneGuessing.guessMissing(in: store, context: context)
        dismiss()
    }

    /// The screenshot demo shows a few things picked.
    private func pickForDemo() {
        guard Launch.isDemo, picked.isEmpty else { return }
        let names: Set<String> = ["Bananas", "Butter", "Sparkling water"]
        picked = Set(items.filter { names.contains($0.displayName) && !service.isOnList($0) }.map(\.objectID))
    }
}
