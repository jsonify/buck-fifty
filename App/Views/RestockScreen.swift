import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// The Restock tab: the checklist for next time. Everything the store remembers, what's due before the next trip
/// first, on the same white cards as the list. Ticking one puts it on the list; unticking takes it off.
struct RestockScreen: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(Profile.self) private var profile
    @Environment(Navigator.self) private var navigator
    // Fetched so the checklist redraws when the list or a trip changes, here or on the other phone.
    @FetchRequest private var entries: FetchedResults<ListEntry>
    @FetchRequest private var openTrips: FetchedResults<Trip>

    init(store: Store) {
        self.store = store
        _entries = FetchRequest(fetchRequest: Fetch.entries(in: store))
        _openTrips = FetchRequest(fetchRequest: Fetch.openTrips(in: store))
    }

    private var service: ListService { ListService(context: context) }

    var body: some View {
        let now = Date()
        let lines = service.restockLines(in: store, now: now)
        let needed = lines.filter { $0.isSuggested && !$0.isOnList }
        let rhythm = service.rhythm(of: store)
        VStack(spacing: 10) {
            ScreenHeader(storeName: store.displayName, title: "Restock",
                         chooseStore: { navigator.choosingStore = true }) {
                StorePresencePill(store: store, openTrips: Array(openTrips))
            }
            TripLCD(label: nextTripLabel(rhythm, now: now),
                    main: needed.isEmpty ? "Everything due is on the list" : "Tick what you need",
                    number: needed.count, unit: "due")
                .padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if lines.isEmpty {
                        Text("Nothing remembered yet. Everything you add and buy is kept here, a checklist for next "
                             + "time.")
                            .sk1Hint()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Restock.Shelf.allCases, id: \.self) { shelf in
                        let shelfLines = lines.filter { $0.shelf == shelf }
                        if !shelfLines.isEmpty {
                            shelfView(shelf, lines: shelfLines, now: now)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            TripBar(title: needed.isEmpty ? "Open the list" : "Add \(needed.count) due",
                    systemImage: needed.isEmpty ? "list.bullet" : "plus",
                    action: {
                        if needed.isEmpty { navigator.tab = .list } else { addNeeded() }
                    }) {
                Button { navigator.tab = .list } label: { Image(systemName: "list.bullet") }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("The list")
            }
        }
        .padding(.top, 4)
        .onAppear { profile.markTried(Milestones.Try.restock) }
    }

    private func nextTripLabel(_ rhythm: ShoppingRhythm, now: Date) -> String {
        if let next = rhythm.nextTrip { return "Next trip \(Restock.until(next, now: now))" }
        if let last = rhythm.lastTrip { return "Last trip \(Restock.ago(last, now: now))" }
        return "No trips yet"
    }

    private func shelfView(_ shelf: Restock.Shelf, lines: [RestockLine], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZoneHeader(title: shelf.title, count: "\(lines.count)", state: shelf == .needed ? .next : .ahead)
            ListCard {
                ForEach(Array(lines.enumerated()), id: \.element.item.objectID) { index, line in
                    restockRow(line, now: now, showsDivider: index > 0)
                }
            }
            if let note = note(for: shelf) {
                Text(note).sk1Hint().fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func restockRow(_ line: RestockLine, now: Date, showsDivider: Bool) -> some View {
        let chip = line.isMuted ? "" : Restock.chip(line.urgency)
        return ItemRow(name: line.item.displayName, detail: detail(line, now: now),
                       isChecked: line.isOnList, showsDivider: showsDivider,
                       accessory: chip.isEmpty ? nil : AnyView(UrgencyTag(text: chip, late: line.urgency == .overdue)),
                       toggle: { toggleOnList(line.item) })
            .onTapGesture { toggleOnList(line.item) }
            .contextMenu {
                if line.isMuted {
                    Button("Suggest when due", systemImage: "bell") { setSuggested(line.item, true) }
                } else {
                    Button("Don't suggest", systemImage: "bell.slash") { setSuggested(line.item, false) }
                }
            }
            .accessibilityAction(named: line.isMuted ? "Suggest when due" : "Don't suggest") {
                setSuggested(line.item, line.isMuted)
            }
    }

    private func detail(_ line: RestockLine, now: Date) -> String {
        var parts: [String] = []
        if line.isOnList { parts.append("On the list") }
        if line.isMuted {
            parts.append("Not suggested")
        } else if line.isSkipped && line.urgency.isNeeded {
            parts.append("Skipped this trip")
        }
        parts.append(line.summary(now: now))
        return parts.joined(separator: " · ")
    }

    private func note(for shelf: Restock.Shelf) -> String? {
        switch shelf {
        case .needed: return "Due is worked out from how often you buy each thing and when you usually shop."
        case .soon: return "Due the trip after next."
        case .staples: return "Bought on most trips. Not due yet, but worth a look."
        case .rest: return "Everything else this store remembers, and what you've said not to suggest. Hold one to "
            + "turn suggesting it on or off."
        }
    }

    private func toggleOnList(_ item: Item) {
        service.toggleOnList(item, by: profile.shopper)
        save()
    }

    private func setSuggested(_ item: Item, _ suggested: Bool) {
        service.setSuggested(item, suggested)
        save()
    }

    private func addNeeded() {
        service.addNeeded(in: store, by: profile.shopper)
        save()
    }

    private func save() {
        do { try service.save() } catch {
            context.rollback()
            print("Buck Fifty: save failed: \(error)")
        }
    }
}

/// DUE, SOON (blue) or LATE (red), on a small tag.
struct UrgencyTag: View {
    let text: String
    var late = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(late ? Hybrid.redFill : Hybrid.blueFill))
    }
}
