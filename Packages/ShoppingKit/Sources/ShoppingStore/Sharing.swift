#if canImport(CoreData)
import CloudKit
import CoreData
import Foundation
import ShoppingCore

/// Sharing a store's list with other iCloud users (CloudKit sharing through NSPersistentCloudKitContainer).
/// Sharing a `Store` shares everything that hangs off it: zones, items, the list, trips and check-offs.
/// On the main actor, as it reads the view context's objects.
@MainActor
public struct SharingService {
    public let persistence: Persistence

    public init(persistence: Persistence) {
        self.persistence = persistence
    }

    private var cloudKit: NSPersistentCloudKitContainer? { persistence.container as? NSPersistentCloudKitContainer }

    /// Whether sharing works here: only with the iCloud stack.
    public var isAvailable: Bool { cloudKit != nil && persistence.cloudKitContainer != nil }

    /// The share a store's list is in, if it is shared (from here, or with you).
    public func existingShare(for store: Store) -> CKShare? {
        guard let cloudKit else { return nil }
        let id = store.objectID
        return (try? cloudKit.fetchShares(matching: [id]))?[id]
    }

    /// Whether the store is in the shared store, i.e. someone shared it with you.
    public func isSharedWithMe(_ store: Store) -> Bool {
        guard let shared = persistence.sharedStore else { return false }
        return store.objectID.persistentStore == shared
    }

    public func summary(for store: Store) -> ShareSummary {
        guard let share = existingShare(for: store) else { return .notShared }
        return ShareSummary(share: share, isOwner: !isSharedWithMe(store))
    }

    /// The store's share, made now if it has none. The list's title is set on it for the invitation.
    public func share(_ store: Store) async throws -> CKShare {
        if let share = existingShare(for: store) { return share }
        guard let cloudKit else { throw SharingError.unavailable }
        let (_, share, _) = try await cloudKit.share([store], to: nil)
        share[CKShare.SystemFieldKey.title] = "\(store.displayName) list" as CKRecordValue
        return share
    }

    /// Saves changes to a share (after the sharing sheet edits it).
    public func persistUpdated(_ share: CKShare) async throws {
        guard let cloudKit, let store = persistence.privateStore else { return }
        try await cloudKit.persistUpdatedShare(share, in: store)
    }

    /// Accepts an invitation to someone else's list: it lands in the shared store and syncs from then on.
    public func accept(_ metadata: CKShare.Metadata) async throws {
        guard let cloudKit, let shared = persistence.sharedStore else { throw SharingError.unavailable }
        _ = try await cloudKit.acceptShareInvitations(from: [metadata], into: shared)
    }

    public enum SharingError: LocalizedError {
        case unavailable

        public var errorDescription: String? {
            "Sharing needs iCloud. Sign in to iCloud in Settings and try again."
        }
    }
}

extension ShareSummary {
    /// The summary of a CloudKit share: the participants other than the current user who have accepted.
    public init(share: CKShare, isOwner: Bool) {
        let others = share.participants.filter { $0 != share.currentUserParticipant }
        let accepted = others.filter { $0.acceptanceStatus == .accepted }
        let names = accepted.map { participant -> String in
            if let components = participant.userIdentity.nameComponents {
                let name = PersonNameComponentsFormatter.localizedString(from: components, style: .short)
                if !name.isEmpty { return name }
            }
            return participant.userIdentity.lookupInfo?.emailAddress ?? "Someone"
        }
        self.init(isShared: true, isOwner: isOwner, participants: names,
                  pending: others.filter { $0.acceptanceStatus == .pending }.count)
    }
}
#endif
