import Foundation

/// Who a list is shared with, as the views show it.
public struct ShareSummary: Equatable, Sendable {
    /// Whether the list is shared at all.
    public var isShared: Bool
    /// Whether this phone's iCloud account owns the share (it was shared from here) or was invited.
    public var isOwner: Bool
    /// The other people on the list who have accepted, by name.
    public var participants: [String]
    /// People invited who haven't accepted yet.
    public var pending: Int

    public init(isShared: Bool, isOwner: Bool = true, participants: [String] = [], pending: Int = 0) {
        self.isShared = isShared
        self.isOwner = isOwner
        self.participants = participants
        self.pending = pending
    }

    public static let notShared = ShareSummary(isShared: false)

    /// Who it's shared with, to follow "Shared with": "Partner", "Partner and Sam", "3 people", "1 invited" while
    /// nobody has accepted yet, or "nobody yet".
    public var people: String {
        switch participants.count {
        case 0: return pending > 0 ? "\(pending) invited" : "nobody yet"
        case 1: return participants[0]
        case 2: return "\(participants[0]) and \(participants[1])"
        default: return "\(participants.count) people"
        }
    }
}
