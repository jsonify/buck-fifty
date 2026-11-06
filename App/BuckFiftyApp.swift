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
    @State private var path: [Store] = []

    /// Posted when another device's changes (or a newly accepted share) are merged in.
    private let remoteChanges = NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
        .receive(on: RunLoop.main)

    var body: some View {
        NavigationStack(path: $path) {
            StoresView()
                .navigationDestination(for: Store.self) { ListScreen(store: $0) }
        }
        .onAppear {
            sharing.refresh(Array(stores))
            // The screenshot demo opens straight onto the Costco list, except for the stores screen itself.
            guard Launch.isDemo, Launch.demoScreen != "stores", path.isEmpty, let costco = stores.first else { return }
            path = [costco]
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
