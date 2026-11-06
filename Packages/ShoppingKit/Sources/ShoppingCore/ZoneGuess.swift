import Foundation

/// A zone as the on-device model sees it: its name and a few items already placed in it, as examples.
public struct ZoneExamples: Sendable, Equatable {
    public var name: String
    public var items: [String]

    public init(name: String, items: [String] = []) {
        self.name = name
        self.items = items
    }
}

/// Everything about guessing a brand-new item's zone that doesn't need the model itself (issue #4): the prompt, and
/// checking the answer is one of the store's zones. The model call lives in the app (Foundation Models), which can
/// only answer with one of `zones`' names; `resolve` still checks, so a bad answer leaves the item unzoned.
public enum ZoneGuess {
    /// The most example items listed per zone.
    public static let examplesPerZone = 4

    /// Tells the model what it's doing.
    public static let instructions = """
        You sort shopping list items into the zones of a store. The zones are the parts of the store in the order \
        a shopper walks through them, not grocery categories. Answer with the one zone where the item is most \
        likely found.
        """

    /// The prompt for `item` at the store called `store`, with its zones in walking order and their examples.
    public static func prompt(item: String, store: String, zones: [ZoneExamples]) -> String {
        var lines = ["Store: \(ItemName.cleaned(store))", "Zones, in walking order:"]
        for zone in zones {
            let examples = zone.items.prefix(examplesPerZone).map(ItemName.cleaned).filter { !$0.isEmpty }
            lines.append(examples.isEmpty ? "- \(zone.name)" : "- \(zone.name): \(examples.joined(separator: ", "))")
        }
        lines.append("Item: \(ItemName.cleaned(item))")
        lines.append("Which zone is it in?")
        return lines.joined(separator: "\n")
    }

    /// The index in `zoneNames` of the zone the model answered (compared normalized), or nil if it isn't one.
    public static func resolve(_ answer: String?, zoneNames: [String]) -> Int? {
        guard let answer else { return nil }
        let key = ItemName.normalized(answer)
        guard !key.isEmpty else { return nil }
        return zoneNames.firstIndex { ItemName.normalized($0) == key }
    }
}
