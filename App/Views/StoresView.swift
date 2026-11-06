import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// The home screen: every store's list, a key to add a store and one for your name.
struct StoresView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(Profile.self) private var profile
    @Environment(SharingModel.self) private var sharing
    @FetchRequest(fetchRequest: Fetch.stores()) private var stores: FetchedResults<Store>
    // Fetched so the counts redraw when any list changes, here or on the other person's phone.
    @FetchRequest(fetchRequest: Fetch.entries()) private var entries: FetchedResults<ListEntry>
    @State private var showingNewStore = false
    @State private var showingProfile = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                SKStatusStrip(title: "Buck Fifty", detail: status)
                if stores.isEmpty {
                    SKWell {
                        Text("Add a store to start its list. A Costco starts with its zones in walking order.")
                            .sk1Hint()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(SK1.Metrics.rowInset)
                    }
                } else {
                    SKGroup(caption: "Lists") {
                        ForEach(stores, id: \.objectID) { store in
                            NavigationLink(value: store) {
                                SKRow(title: store.displayName, subtitle: subtitle(for: store)) {
                                    SKChip("\(remaining(in: store))", minWidth: 36)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                SKKeyGroup {
                    SKCaptionedKey("New store", systemImage: "plus", variant: .orange) { showingNewStore = true }
                    SKCaptionedKey(profile.name.isEmpty ? "You" : profile.name, systemImage: "person.crop.circle",
                                   variant: .charcoal) { showingProfile = true }
                }
            }
            .padding(16)
        }
        .sk1Chassis()
        .navigationTitle("Buck Fifty")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNewStore) { NewStoreSheet() }
        .sheet(isPresented: $showingProfile) { ProfileSheet() }
    }

    private var status: String {
        let left = entries.filter { !$0.isChecked }.count
        return "\(left) TO GET"
    }

    private func remaining(in store: Store) -> Int {
        entries.filter { !$0.isChecked && $0.item?.store == store }.count
    }

    private func subtitle(for store: Store) -> String {
        let n = remaining(in: store)
        let count = n == 0 ? "Nothing on the list" : n == 1 ? "1 thing to get" : "\(n) things to get"
        let share = sharing.summary(for: store)
        return share.isShared ? "\(count) · Shared with \(share.people)" : count
    }
}

/// A new store: its name, and its zones from the defaults.
struct NewStoreSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        SheetScaffold(title: "New store") {
            CaptionedField(caption: "Name", note: note) {
                SKTextField("Store name", text: $name, prompt: "Costco")
                    .onSubmit(create)
            }
        } actions: {
            Button("Cancel") { dismiss() }.buttonStyle(.sk1Key())
            Spacer()
            Button("Create", action: create)
                .buttonStyle(.sk1Key(.orange))
                .disabled(ItemName.cleaned(name).isEmpty)
        }
        .presentationDetents([.medium])
    }

    private var note: String {
        let zones = DefaultZones.zones(forStoreNamed: name)
        return "Starts with these zones, which you can change: " + zones.joined(separator: ", ") + "."
    }

    private func create() {
        guard !ItemName.cleaned(name).isEmpty else { return }
        let service = ListService(context: context)
        service.createStore(named: name)
        try? service.save()
        dismiss()
    }
}

/// Your name, as the people you share a list with see it.
struct ProfileSheet: View {
    @Environment(Profile.self) private var profile
    @Environment(SharingModel.self) private var sharing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var profile = profile
        SheetScaffold(title: "You", detail: profile.shopper.initials) {
            CaptionedField(caption: "Your name",
                           note: "Shown next to what you add and check off, and on your trips.") {
                SKTextField("Your name", text: $profile.name, prompt: "Jason")
                    .textContentType(.givenName)
                    .onSubmit { dismiss() }
            }
            SKGroup(caption: "Experimental", note: mappingNote) {
                SKRow(title: "Map the store", subtitle: "Builds a floor plan from your trips") {
                    Toggle(isOn: $profile.mapsStore) { EmptyView() }
                        .toggleStyle(.sk1Switch)
                        .disabled(!StoreMapper.isAvailable)
                        .accessibilityLabel("Map the store")
                }
            }
            .onChange(of: profile.mapsStore) { _, on in
                if on { StoreMapper.requestAccess() }
            }
        } actions: {
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.sk1Key(.orange))
        }
    }

    private var mappingNote: String {
        guard StoreMapper.isAvailable else { return "This iPhone has no pedometer or compass to map with." }
        return "Tap Start trip at the door and keep the app open: your steps and compass trace your walk, and every "
            + "check-off becomes a point. After about ten trips the map shows where everything is. Steel shelves "
            + "bend the compass, so expect it to wander. It asks for Motion & Fitness access; the walk stays on this "
            + "phone and in your shared list."
    }
}
