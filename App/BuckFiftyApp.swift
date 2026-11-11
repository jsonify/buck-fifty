import Combine
import CoreData
import SwiftUI
import ShoppingStore

@main
struct BuckFiftyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, model.persistence.viewContext)
                .environment(model.profile)
                .environment(model.sharing)
        }
    }
}

struct RootView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(SharingModel.self) private var sharing
    @Environment(Profile.self) private var profile
    @FetchRequest(fetchRequest: Fetch.stores()) private var stores: FetchedResults<Store>
    // Fetched so the tab bar's Restock count and the store you're in follow every change, here or on the other phone.
    @FetchRequest(fetchRequest: Fetch.entries()) private var entries: FetchedResults<ListEntry>
    @FetchRequest(fetchRequest: Fetch.trips()) private var trips: FetchedResults<Trip>
    @State private var navigator = Navigator()
    @State private var showingNewStore = false
    /// The tour, on first launch.
    @State private var showingTour = false
    /// The guide (only opened from here by the screenshot demo; You opens it otherwise).
    @State private var showingGuide = false

    /// Posted when another device's changes (or a newly accepted share) are merged in.
    private let remoteChanges = NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
        .receive(on: RunLoop.main)

    /// The store every tab is about: the one chosen, else the one you're in, else the first.
    private var store: Store? {
        if let chosen = stores.first(where: { $0.id?.uuidString == navigator.storeID }) { return chosen }
        let mine = trips.first { $0.endedAt == nil && $0.shopperID == profile.id }?.store
        return mine ?? stores.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let store {
                    screen(for: store)
                } else {
                    NoStoreScreen { showingNewStore = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            AppTabBar(selection: $navigator.tab, badges: store.map { [.restock: dueCount(at: $0)] } ?? [:])
        }
        .sk1Chassis()
        .environment(navigator)
        .sheet(isPresented: $navigator.choosingStore) {
            StoreChooserSheet(current: store) { showingNewStore = true }
                .environment(navigator)
        }
        .sheet(isPresented: $showingNewStore) { NewStoreSheet { navigator.choose($0) } }
        .onAppear {
            sharing.refresh(Array(stores))
            if Launch.isDemo {
                showingTour = Launch.demoScreen == "tour"
                showingGuide = Launch.demoScreen == "guide"
                navigator.storeID = stores.first?.id?.uuidString ?? ""
                navigator.tab = Launch.demoTab
            } else if !profile.hasSeenTour {
                showingTour = true
            }
        }
        .fullScreenCover(isPresented: $showingTour) { TourSheet() }
        .sheet(isPresented: $showingGuide) { GuideSheet() }
        .onReceive(remoteChanges) { _ in sharing.refresh(Array(stores)) }
        .onChange(of: stores.count) { sharing.refresh(Array(stores)) }
        .alert("Sharing", isPresented: Binding(get: { sharing.errorMessage != nil },
                                                set: { if !$0 { sharing.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sharing.errorMessage ?? "")
        }
    }

    /// Each tab gets its own view per store, so its fetches and state start fresh when the store changes.
    @ViewBuilder private func screen(for store: Store) -> some View {
        switch navigator.tab {
        case .home: HomeScreen(store: store).id(store.objectID)
        case .list: ListScreen(store: store).id(store.objectID)
        case .map: MapScreen(store: store).id(store.objectID)
        case .restock: RestockScreen(store: store).id(store.objectID)
        case .you: YouScreen(store: store)
        }
    }

    private func dueCount(at store: Store) -> Int {
        ListService(context: context).neededNotOnList(in: store).count
    }
}
