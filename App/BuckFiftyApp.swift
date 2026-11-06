import SwiftUI
import ShoppingStore

@main
struct BuckFiftyApp: App {
    private let persistence: Persistence
    @State private var profile: Profile

    init() {
        let profile = Profile()
        if Launch.isDemo { profile.name = "Jason" }
        persistence = AppData.makePersistence(shopper: profile.shopper)
        _profile = State(initialValue: profile)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environment(profile)
        }
    }
}

struct RootView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var path: [Store] = []

    var body: some View {
        NavigationStack(path: $path) {
            StoresView()
                .navigationDestination(for: Store.self) { ListScreen(store: $0) }
        }
        .onAppear {
            // The screenshot demo opens straight onto the Costco list, except for the stores screen itself.
            guard Launch.isDemo, Launch.demoScreen != "stores", path.isEmpty,
                  let costco = try? context.fetch(Fetch.stores()).first else { return }
            path = [costco]
        }
    }
}
