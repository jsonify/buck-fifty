#if canImport(CoreData)
import CloudKit
import CoreData
import Foundation

/// The Core Data stack.
///
/// In the app it is an `NSPersistentCloudKitContainer` with two stores: the private one, mirrored to your private
/// iCloud database, where your own lists live; and the shared one, mirrored to the shared database, where lists
/// other people share with you live. Changes arrive by CloudKit push and are merged into the view context, so a
/// shared list updates on both phones within seconds.
public final class Persistence {
    public enum Kind {
        /// Nothing written to disk: tests, previews and the screenshot demo.
        case inMemory
        /// A local SQLite store in `directory`, not synced.
        case local(directory: URL)
        /// Private and shared SQLite stores in `directory`, mirrored to the iCloud container `containerIdentifier`.
        case cloudKit(containerIdentifier: String, directory: URL)
    }

    public let container: NSPersistentContainer
    public var viewContext: NSManagedObjectContext { container.viewContext }
    /// The CloudKit container, when syncing.
    public let cloudKitContainer: CKContainer?
    /// Where your own lists live (the only store when not syncing).
    public private(set) var privateStore: NSPersistentStore?
    /// Where lists shared with you live, when syncing.
    public private(set) var sharedStore: NSPersistentStore?

    public init(_ kind: Kind) throws {
        var privateURL: URL?
        var sharedURL: URL?
        switch kind {
        case .inMemory:
            container = NSPersistentContainer(name: "BuckFifty", managedObjectModel: ShoppingModel.model)
            let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
            cloudKitContainer = nil
        case .local(let directory):
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            container = NSPersistentContainer(name: "BuckFifty", managedObjectModel: ShoppingModel.model)
            let url = directory.appendingPathComponent("BuckFifty.sqlite")
            container.persistentStoreDescriptions = [Persistence.description(url: url, scope: nil, identifier: nil)]
            privateURL = url
            cloudKitContainer = nil
        case .cloudKit(let identifier, let directory):
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            container = NSPersistentCloudKitContainer(name: "BuckFifty", managedObjectModel: ShoppingModel.model)
            let p = directory.appendingPathComponent("Private.sqlite")
            let s = directory.appendingPathComponent("Shared.sqlite")
            container.persistentStoreDescriptions = [
                Persistence.description(url: p, scope: .private, identifier: identifier),
                Persistence.description(url: s, scope: .shared, identifier: identifier),
            ]
            privateURL = p
            sharedURL = s
            cloudKitContainer = CKContainer(identifier: identifier)
        }
        try Persistence.load(container)
        let stores = container.persistentStoreCoordinator.persistentStores
        privateStore = privateURL.flatMap { url in stores.first { $0.url == url } } ?? stores.first
        sharedStore = sharedURL.flatMap { url in stores.first { $0.url == url } }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "app"
    }

    /// A store description with history tracking and remote-change notifications on, which syncing needs.
    private static func description(url: URL, scope: CKDatabase.Scope?, identifier: String?) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if let scope, let identifier {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: identifier)
            options.databaseScope = scope
            description.cloudKitContainerOptions = options
        }
        return description
    }

    private static func load(_ container: NSPersistentContainer) throws {
        let failure = LoadFailure()
        // Stores load synchronously unless a description asks otherwise.
        container.loadPersistentStores { _, error in
            if let error { failure.error = error }
        }
        if let error = failure.error { throw error }
    }

    private final class LoadFailure {
        var error: Error?
    }
}
#endif
