import Foundation

/// A pharmacy locker order from the pharmacy's text ("Pickup Code: AVQHTH … Please pick-up within 5 days"): the code
/// that opens the locker, who it's for, and how long it waits. It goes on the list at the pharmacy lockers.
public struct LockerPickup: Sendable, Equatable {
    /// The name the pickup goes on the list under.
    public static let itemName = "Pharmacy locker pickup"

    public var code: String
    /// Who the order is for ("Alise"), when the text says.
    public var name: String?
    /// How many days the locker holds it, when the text says.
    public var days: Int?

    public init(code: String, name: String? = nil, days: Int? = nil) {
        self.code = code
        self.name = name
        self.days = days
    }

    /// The pickup in a pharmacy's text, or nil when it has no pickup code. Works on the text as copied or pasted on
    /// one line.
    public static func parse(_ text: String) -> LockerPickup? {
        guard let code = firstMatch(#"pick[\s-]*up\s+code\s*[:#]?\s*([A-Za-z0-9]{4,12})\b"#, in: text)
                ?? firstMatch(#"locker\s+code\s*[:#]?\s*([A-Za-z0-9]{4,12})\b"#, in: text) else { return nil }
        let name = firstMatch(#"\bfor\s*:\s*([A-Za-z][A-Za-z'\-]*)"#, in: text).map(\.capitalized)
        let days = firstMatch(#"within\s+(\d{1,2})\s+days?"#, in: text).flatMap { Int($0) }
        return LockerPickup(code: code.uppercased(), name: name, days: days)
    }

    /// The note on the list: the code, who it's for and the last day to pick it up ("Code AVQHTH · Alise · by Nov 18").
    public func note(receivedAt: Date, calendar: Calendar = .current) -> String {
        var parts = ["Code \(code)"]
        if let name { parts.append(name) }
        if let days, let last = calendar.date(byAdding: .day, value: days, to: receivedAt) {
            let format = Date.FormatStyle(date: .omitted, time: .omitted).month(.abbreviated).day()
            parts.append("by \(last.formatted(format))")
        }
        return parts.joined(separator: " · ")
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
