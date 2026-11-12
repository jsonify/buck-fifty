import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// Past items: everything the store remembers, opened from the List tab, so a new list can start clean and still be
/// built in a few taps. Usual (what you buy most, most first), Running low (what Restock says runs out before the next
/// trip), Last trip, or everything A to Z; the find field narrows it. Tap an item to put it on the list, again to take
/// it off.
struct PastItemsSheet: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Profile.self) private var profile
    @FetchRequest private var items: FetchedResults<Item>
    @FetchRequest private var entries: FetchedResults<ListEntry>
    @State private var query = ""
    @State private var filter: PastItemsFilter = .usual

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
        let onList = entries.filter { !$0.isChecked }.count
        SheetScaffold(title: "Past items", detail: "\(bought) BOUGHT BEFORE") {
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
                SKGroup(caption: caption(shown.count), note: "Tap to put it on the list; tap again to take it off.") {
                    ForEach(shown, id: \.ref.objectID) { past in
                        Button { toggle(past.ref) } label: {
                            SKRow(title: past.name, subtitle: subtitle(past, now: now)) {
                                SKChip(past.isOnList ? "ON LIST" : "ADD", minWidth: 64)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(past.isOnList ? "\(past.name), on the list" : past.name)
                        .accessibilityHint(past.isOnList ? "Takes it off the list" : "Puts it on the list")
                    }
                }
            }
        } actions: {
            Text(onList == 1 ? "1 on the list" : "\(onList) on the list")
                .sk1Hint()
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.sk1Key(.orange))
        }
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

    private func toggle(_ item: Item) {
        service.toggleOnList(item, by: profile.shopper)
        try? service.save()
    }
}
