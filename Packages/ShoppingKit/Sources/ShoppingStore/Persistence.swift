#if canImport(CoreData)
import CoreData
import Foundation

/// The Core Data stack.
public final class Persistence {
    public enum Kind {
        /// Nothing written to disk: tests, previews and the screenshot demo.
        case inMemory
        /// A local SQLite store in `directory`.
        case local(directory: URL)
    }

    public let container: NSPersistentContainer
    public var viewContext: NSManagedObjectContext { container.viewContext }

    public init(_ kind: Kind) throws {
        switch kind {
        case .inMemory:
            container = NSPersistentContainer(name: "BuckFifty", managedObjectModel: ShoppingModel.model)
            let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        case .local(let directory):
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            container = NSPersistentContainer(name: "BuckFifty", managedObjectModel: ShoppingModel.model)
            let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("BuckFifty.sqlite"))
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            container.persistentStoreDescriptions = [description]
        }
        try Persistence.load(container)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func load(_ container: NSPersistentContainer) throws {
        var failure: Error?
        // Stores load synchronously unless a description asks otherwise.
        container.loadPersistentStores { _, error in
            if let error { failure = error }
        }
        if let failure { throw failure }
    }
}
#endif
