import Foundation

/// What a trip looked for and didn't find ("Not here"): it stays on the list for the next trip, under its own heading
/// at the bottom so the count on the LCD is only what's still to find. Marks are kept by entry id and cleared when the
/// next trip starts.
public struct NotHereMarks: Equatable, Sendable {
    public private(set) var ids: Set<String>

    public init(_ ids: Set<String> = []) {
        self.ids = ids
    }

    public func contains(_ id: String?) -> Bool {
        guard let id else { return false }
        return ids.contains(id)
    }

    public mutating func mark(_ id: String?) {
        if let id { ids.insert(id) }
    }

    public mutating func unmark(_ id: String?) {
        if let id { ids.remove(id) }
    }

    /// `rows` split into what's still in play this trip and what wasn't here, each in the order given.
    public func split<Row>(_ rows: [Row], id: (Row) -> String?) -> (inPlay: [Row], notHere: [Row]) {
        var inPlay: [Row] = []
        var notHere: [Row] = []
        for row in rows {
            if contains(id(row)) { notHere.append(row) } else { inPlay.append(row) }
        }
        return (inPlay, notHere)
    }
}
