import Foundation

/// How item names are tidied and compared.
public enum ItemName {
    /// The name as typed, without leading or trailing whitespace and with runs of whitespace collapsed to one space.
    /// Case is kept ("Kirkland pesto").
    public static func cleaned(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The key two names are the same item by: cleaned, lower-cased, accents and widths folded
    /// ("  Crème  Fraîche" and "creme fraiche" match).
    public static func normalized(_ name: String) -> String {
        cleaned(name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}

/// Autocomplete over the items a store already remembers.
public enum ItemSuggester {
    /// The candidates that match `query`, best first, at most `limit`. A candidate matches when its normalized name
    /// equals the query, starts with it, has a word starting with it, or contains it, ranked in that order; ties go
    /// to the shorter name, then alphabetical. An empty query matches nothing.
    public static func suggestions<T>(for query: String, in candidates: [T], limit: Int = 5,
                                      name: (T) -> String) -> [T] {
        let q = ItemName.normalized(query)
        guard !q.isEmpty, limit > 0 else { return [] }
        var ranked: [(rank: Int, key: String, value: T)] = []
        for candidate in candidates {
            let key = ItemName.normalized(name(candidate))
            let rank: Int
            if key == q {
                rank = 0
            } else if key.hasPrefix(q) {
                rank = 1
            } else if key.split(separator: " ").contains(where: { $0.hasPrefix(q) }) {
                rank = 2
            } else if key.contains(q) {
                rank = 3
            } else {
                continue
            }
            ranked.append((rank, key, candidate))
        }
        ranked.sort { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.key.count != b.key.count { return a.key.count < b.key.count }
            return a.key < b.key
        }
        return ranked.prefix(limit).map(\.value)
    }
}
