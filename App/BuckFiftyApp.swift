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
    @FetchRequest(fetchRequest: Fetch.stores()) private var stores: FetchedResults<Store>
    @State private var path: [ListRoute] = []

    /// Posted when another device's changes (or a newly accepted share) are merged in.
    private let remoteChanges = NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
        .receive(on: RunLoop.main)

    var body: some View {
        NavigationStack(path: $path) {
            StoresView(path: $path)
                .navigationDestination(for: ListRoute.self) { ListScreen(store: $0.store, mode: $0.mode) }
        }
        .onAppear {
            sharing.refresh(Array(stores))
            // The screenshot demo opens straight onto the Costco list, except for the stores screen itself.
            guard Launch.isDemo, Launch.demoScreen != "stores", path.isEmpty, let costco = stores.first else { return }
            path = [ListRoute(store: costco, mode: Launch.demoScreen == "restock" ? .restock : .list)]
        }
        .onReceive(remoteChanges) { _ in sharing.refresh(Array(stores)) }
        .onChange(of: stores.count) { sharing.refresh(Array(stores)) }
        .alert("Sharing", isPresented: Binding(get: { sharing.errorMessage != nil },
                                                set: { if !$0 { sharing.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sharing.errorMessage ?? "")
        }
    }
}

/// Which list to open, and how: the list itself, or its restock checklist.
struct ListRoute: Hashable {
    let store: Store
    var mode: ListMode = .list
}

/// The two views of a store's list: what's on it, and the restock checklist of everything the store remembers.
enum ListMode: Hashable {
    case list
    case restock
}
