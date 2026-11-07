import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

// Milestones (issue #23): what Buck Fifty has learned about a store, what's coming and how soon, and features to try.
// The home screen shows them one of two ways, chosen in Settings: a Coming up checklist, or a level that rises as
// they're done. Either way, a feature that just switched on is announced once at the top of home, and Milestones (from
// home or Settings) lists them all.

/// A store's milestones, with what only the app knows: Map the store, whether the list is shared, what's been tried.
@MainActor
enum MilestoneBoard {
    static func milestones(for store: Store, context: NSManagedObjectContext, profile: Profile,
                           sharing: SharingModel) -> [Milestone] {
        ListService(context: context).milestones(for: store, mapsStore: profile.mapsStore,
                                                 isShared: sharing.summary(for: store).isShared, tried: profile.tried)
    }
}

/// A guide part to open, for `sheet(item:)`.
struct GuideJump: Identifiable {
    let id: String
}

/// One milestone as a row: its title, how far along it is or what it does, and a chip (2/3, DONE, TRY).
struct MilestoneRow: View {
    let milestone: Milestone

    var body: some View {
        SKRow(title: milestone.title, subtitle: subtitle) {
            HStack(spacing: 8) {
                if milestone.isDone {
                    SKLamp(color: .teal, lit: true, label: "\(milestone.title) is on", blinking: false)
                }
                SKChip(chip, minWidth: 52)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens how it works in the guide")
    }

    private var subtitle: String {
        if milestone.isDone { return milestone.does }
        if milestone.blockedBy != nil { return "\(milestone.status). \(milestone.howTo)" }
        if let eta = milestone.eta { return "\(eta). \(milestone.howTo)" }
        return milestone.howTo
    }

    private var chip: String {
        if milestone.isDone { return "DONE" }
        if milestone.blockedBy != nil { return "OFF" }
        if milestone.kind == .tryIt { return "TRY" }
        return "\(milestone.progress)/\(milestone.target)"
    }
}

/// The level on LCD glass (the Levels style): its number and title, a segment for every milestone (lit when done),
/// and how many more to the next level.
struct LevelMeter: View {
    let level: MilestoneLevel
    let total: Int

    var body: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        SKLCD {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("LV \(level.number)")
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    Text(level.title.uppercased())
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1)
                    Spacer()
                    Text("\(level.done)/\(total)")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
                HStack(spacing: 3) {
                    ForEach(0..<total, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(ink.opacity(index < level.done ? 0.9 : 0.15))
                            .frame(height: 9)
                    }
                }
                Text(nextLine)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(height: 82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(level.number), \(level.title). \(level.done) of \(total) milestones. \(nextLine)")
    }

    private var nextLine: String {
        guard let toNext = level.toNext, let next = level.nextTitle else { return "EVERY MILESTONE DONE" }
        return "\(toNext) MORE TO \(next.uppercased())"
    }
}

/// What just switched on at a store, announced once at the top of home: each with what it does, Got it to put them
/// away and a tap for how it works.
struct NewMilestones: View {
    let store: Store
    let milestones: [Milestone]
    let onGuide: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        SKGroup(caption: milestones.count == 1 ? "New at \(store.displayName)"
                    : "New at \(store.displayName) · \(milestones.count)",
                note: "Buck Fifty learned enough from your trips to switch these on. Tap one for how it works.") {
            ForEach(milestones.prefix(3)) { milestone in
                Button { onGuide(milestone.guidePart) } label: { MilestoneRow(milestone: milestone) }
                    .buttonStyle(.plain)
            }
            SKRow(title: milestones.count > 3 ? "And \(milestones.count - 3) more in Milestones"
                    : "Milestones has them all") {
                Button("Got it", action: onDismiss).buttonStyle(.sk1Key(size: .small))
            }
        }
    }
}

/// Every milestone for a store: the Levels style's meter, then what it learns from shopping and what to try, each with
/// how far along it is. A tap opens how it works in the guide.
struct MilestonesSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Profile.self) private var profile
    @Environment(SharingModel.self) private var sharing
    @FetchRequest(fetchRequest: Fetch.stores()) private var stores: FetchedResults<Store>
    // Fetched so the sheet redraws as trips end, here or on the other person's phone.
    @FetchRequest(fetchRequest: Fetch.trips()) private var trips: FetchedResults<Trip>
    /// The store shown, by its id.
    @State private var storeID: String
    @State private var guide: GuideJump?

    init(store: Store?) {
        _storeID = State(initialValue: store.map(Self.key) ?? "")
    }

    var body: some View {
        let store = stores.first { Self.key($0) == storeID } ?? stores.first
        let all = store.map { MilestoneBoard.milestones(for: $0, context: context, profile: profile, sharing: sharing) } ?? []
        let done = all.filter(\.isDone).count
        SheetScaffold(title: "Milestones", detail: "\(done) OF \(all.count) DONE") {
            if let store {
                if stores.count > 1 {
                    CaptionedField(caption: "Store", note: "Each store learns from its own trips.") {
                        SKPicker(selection: Binding(get: { Self.key(store) }, set: { storeID = $0 }),
                                 options: stores.map { SKPicker<String>.Option(Self.key($0), $0.displayName) })
                    }
                }
                if profile.milestoneStyle == .levels {
                    LevelMeter(level: Milestones.level(done: done, of: all.count), total: all.count)
                }
                group("Learning \(store.displayName)",
                      note: "These switch on by themselves as you shop. Each counts this store's trips, on every phone "
                        + "it's shared with.",
                      all.filter { $0.kind == .earned })
                group("Try it",
                      note: "These are there already. Each is ticked the first time you use it on this phone.",
                      all.filter { $0.kind == .tryIt })
            } else {
                Text("Add a store, and its milestones show here: what Buck Fifty learns from your trips, and features "
                     + "to try.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.sk1Key(.orange))
        }
        .sheet(item: $guide) { GuideSheet(startAt: $0.id) }
        .onAppear {
            // What's listed here has been seen: no need to announce it on home as well.
            if let store { profile.markSeen(all.filter { $0.isDone && $0.kind == .earned }, of: store) }
        }
    }

    private static func key(_ store: Store) -> String { store.id?.uuidString ?? "" }

    private func group(_ caption: String, note: String, _ milestones: [Milestone]) -> some View {
        let done = milestones.filter(\.isDone).count
        return SKGroup(caption: "\(caption) · \(done) of \(milestones.count)", note: note) {
            ForEach(milestones) { milestone in
                Button { guide = GuideJump(id: milestone.guidePart) } label: { MilestoneRow(milestone: milestone) }
                    .buttonStyle(.plain)
            }
        }
    }
}
