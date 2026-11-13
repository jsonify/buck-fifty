import AppIntents
import CoreData
import ShoppingCore
import ShoppingStore

/// Save locker code, for Shortcuts: give it the pharmacy's locker text and the pickup goes on the list at the
/// pharmacy lockers, with its code in the note. An automation (Automation → Message, from the pharmacy, containing
/// "locker") runs it for every text, so the code is on the list without opening Messages. Apps can't read texts
/// themselves; Shortcuts hands this one over.
struct SaveLockerCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Save locker code"
    static let description = IntentDescription(
        "Reads a pharmacy locker text and puts the pickup on the list at the pharmacy lockers, with its code.")
    static let openAppWhenRun = false

    @Parameter(title: "Message")
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save the locker code in \(\.$message)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let pickup = LockerPickup.parse(message) else {
            return .result(dialog: "There's no pickup code in that message.")
        }
        let model = AppModel.shared
        let context = model.persistence.viewContext
        let service = ListService(context: context)
        let stores = (try? context.fetch(Fetch.stores())) ?? []
        guard let store = service.lockerStore(among: stores) else {
            return .result(dialog: "Add a store in Buck Fifty first.")
        }
        service.addLockerPickup(pickup, to: store, by: model.profile.shopper)
        try service.save()
        return .result(dialog: "Locker code \(pickup.code) is on the \(store.displayName) list.")
    }
}

struct BuckFiftyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SaveLockerCodeIntent(),
                    phrases: ["Save a locker code in \(.applicationName)"],
                    shortTitle: "Save locker code",
                    systemImageName: "lock")
    }
}
