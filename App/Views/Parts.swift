import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore

// The parts every tab is built from (issue #25): the SK-1 chassis, LCD and keys, with the list on white cards in the
// Costco-style accents. Each colour means one thing everywhere:
// orange is the one key and the next stop or item; blue is done, walked, walk numbers and links; red is Add, LATE,
// moved and the tab you're on; the teal lamp is someone in the store.

/// The hybrid's colours, beside SK1Kit's tokens.
enum Hybrid {
    /// A list card: white in light, a step up from the chassis in dark.
    static func card(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(sk1Hex: 0x3A3833) : .white }
    /// The hairline between rows on a card.
    static func line(_ scheme: ColorScheme) -> Color { Color(sk1Hex: scheme == .dark ? 0x2C2A27 : 0xECE9E2) }
    /// Fills with white on them (check marks, walk numbers): blue.
    static let blueFill = Color(sk1Hex: 0x1F6FBF)
    /// Blue text: links and the store chip.
    static func blue(_ scheme: ColorScheme) -> Color { Color(sk1Hex: scheme == .dark ? 0x8CC0F5 : 0x0A5BA8) }
    /// Fills with white on them (Add, LATE): red.
    static let redFill = Color(sk1Hex: 0xD2192E)
    /// Red text: the tab you're on, something that moved.
    static func red(_ scheme: ColorScheme) -> Color { Color(sk1Hex: scheme == .dark ? 0xFF8A80 : 0xB3261E) }
    /// The next stop or item: SK-1 orange.
    static let orange = Color(sk1Hex: SK1.orange)
    /// Orange text, darker so it reads on the chassis.
    static func orangeText(_ scheme: ColorScheme) -> Color { Color(sk1Hex: scheme == .dark ? 0xFF9A66 : 0xB8400C) }
}

// MARK: Header

/// The top of every tab: the store chip (tap to choose the store), the screen's title, and a pill on the right.
struct ScreenHeader<Trailing: View>: View {
    let storeName: String?
    let title: String
    let chooseStore: () -> Void
    @ViewBuilder var trailing: Trailing
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: chooseStore) {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(storeName ?? "Choose a store").lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Hybrid.blue(scheme))
                    .frame(minHeight: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Store: \(storeName ?? "none")")
                .accessibilityHint("Choose the store")
                Text(title)
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(-0.4)
                    .sk1Ink()
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

/// Who's in the store (a lit, blinking teal lamp), or who the list is shared with (unlit).
struct PresencePill: View {
    let text: String
    let lit: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            SKLamp(color: .teal, lit: lit, size: 7, label: text, blinking: lit)
            Text(text).font(.system(size: 12, weight: .bold)).lineLimit(1).sk1Ink()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Capsule().fill(Hybrid.card(scheme)).shadow(color: .black.opacity(0.12), radius: 1, y: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: The LCD

/// One cell of the LCD's strip: a stop of the walk, or a day of the week.
struct StripCell: Hashable {
    enum Fill: Hashable { case full, half, empty }
    var fill: Fill
    /// Outlined in full ink (the next stop, the next trip's day).
    var marked = false
    /// A letter in the cell (the week's days).
    var text: String?
}

/// The one LCD every tab shares: a small label, a main line, a seven-segment number with its unit, and a strip with
/// a legend under it (the walk's stops in the store, the week at home).
struct TripLCD: View {
    let label: String
    let main: String
    let number: Int?
    let unit: String
    var strip: [StripCell] = []
    var legend: [String] = []

    private var ink: Color { Color(sk1Hex: SK1.lcdInk) }

    var body: some View {
        SKLCD {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(1)
                        Text(main.uppercased())
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .tracking(0.6)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    if let number {
                        HStack(alignment: .bottom, spacing: 4) {
                            SKSevenSegment(String(format: "%02d", min(number, 999)), digitHeight: 28, color: ink)
                            Text(unit.uppercased())
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .tracking(1)
                        }
                    }
                }
                if !strip.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(strip.enumerated()), id: \.offset) { _, cell in
                            cellView(cell)
                        }
                    }
                    .frame(height: 16)
                }
                if !legend.isEmpty {
                    HStack {
                        ForEach(Array(legend.enumerated()), id: \.offset) { index, text in
                            if index > 0 { Spacer(minLength: 4) }
                            Text(text.uppercased())
                        }
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .lineLimit(1)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(height: strip.isEmpty ? 74 : 112)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, main, number.map { "\($0) \(unit)" }].compactMap { $0 }.joined(separator: ", "))
    }

    private func cellFill(_ fill: StripCell.Fill) -> Color {
        switch fill {
        case .full: return ink
        case .half: return ink.opacity(0.5)
        case .empty: return .clear
        }
    }

    private func cellView(_ cell: StripCell) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        return shape.fill(cellFill(cell.fill))
            .overlay(shape.stroke(ink.opacity(cell.marked || cell.fill != .empty ? 1 : 0.35),
                                  lineWidth: cell.marked ? 1.5 : 1))
            .overlay {
                if let text = cell.text {
                    Text(text)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(cell.fill == .full ? Color(sk1Hex: SK1.glassTop) : ink)
                }
            }
            .frame(maxWidth: .infinity)
    }
}

// MARK: Adding

/// The add field: type a name, Return or + adds it.
struct AddBar: View {
    @Binding var draft: String
    let prompt: String
    let add: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            SKTextField("Add an item", text: $draft, prompt: prompt)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(add)
            Button(action: add) { Image(systemName: "plus") }
                .buttonStyle(.sk1Key())
                .accessibilityLabel("Add")
                .disabled(ItemName.cleaned(draft).isEmpty)
        }
    }
}

// MARK: The list

/// A white card holding rows, with hairlines between them (each row draws its own, see `ItemRow.showsDivider`).
struct ListCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Hybrid.card(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.08), radius: 1.5, y: 1)
    }
}

/// A zone's heading over its card: its name in small capitals and how many are left.
struct ZoneHeader: View {
    let title: String
    let count: String
    var state: Walk.StopState = .ahead
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(count).font(.system(size: 12, weight: .semibold)).sk1Ink(soft: true)
        }
        .frame(minHeight: 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var color: Color {
        let p = SK1.palette(for: scheme)
        switch state {
        case .next: return Hybrid.orangeText(scheme)
        case .done: return Color(sk1Hex: p.inkSoft)
        case .ahead: return Color(sk1Hex: p.ink)
        }
    }
}

/// The round check mark: an empty ring, or a blue disc with a tick.
struct CheckCircle: View {
    let isOn: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(Hybrid.blueFill)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .black)).foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Color(sk1Hex: SK1.palette(for: scheme).inkSoft), lineWidth: 2)
            }
        }
        .frame(width: 26, height: 26)
    }
}

/// An item's walk number, as on its pin on the map: blue, or orange for the next thing to get.
struct WalkBadge: View {
    let number: Int
    var isNext = false

    var body: some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .minimumScaleFactor(0.7)
            .frame(width: 24, height: 24)
            .background(PinShape().fill(isNext ? Hybrid.orange : Hybrid.blueFill))
            .accessibilityLabel(isNext ? "Next, stop \(number)" : "Stop \(number)")
    }
}

/// A map pin: round but for its bottom-left corner, which points at the spot.
struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r * 0.3,
                                      bottomTrailingRadius: r, topTrailingRadius: r)
            .path(in: rect)
    }
}

/// How a row's detail line reads: plain, an alert (it moved, it's late), or information (a guessed zone).
enum DetailTone { case soft, alert, info }

/// One item on a card: the check mark, its name and detail, an accessory, how many, and its walk number.
struct ItemRow: View {
    let name: String
    var detail: String?
    var detailTone: DetailTone = .soft
    var quantity: Int64 = 1
    let isChecked: Bool
    var number: Int?
    var isNext = false
    var showsDivider = false
    var accessory: AnyView?
    let toggle: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) { CheckCircle(isOn: isChecked).frame(width: 44, height: 44) }
                .buttonStyle(.plain)
                .padding(.horizontal, -9)
                .accessibilityLabel(isChecked ? "\(name), in the cart" : name)
                .accessibilityHint(isChecked ? "Takes it out of the cart" : "Checks it off")
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .strikethrough(isChecked)
                    .sk1Ink(soft: isChecked)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let accessory { accessory }
            if quantity > 1 {
                Text("×\(quantity)").font(.system(size: 13, weight: .bold)).sk1Ink(soft: true)
            }
            if let number, !isChecked { WalkBadge(number: number, isNext: isNext) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if showsDivider { Rectangle().fill(Hybrid.line(scheme)).frame(height: 1) }
        }
    }

    private var detailColor: Color {
        switch detailTone {
        case .soft: return Color(sk1Hex: SK1.palette(for: scheme).inkSoft)
        case .alert: return Hybrid.red(scheme)
        case .info: return Hybrid.blue(scheme)
        }
    }
}

/// A stop on the route rail: its number, blue once it's done, orange when it's next, open when it's ahead.
struct RailNode: View {
    let text: String
    let state: Walk.StopState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = SK1.palette(for: scheme)
        Text(text)
            .font(.system(size: 9.5, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(state == .ahead ? Color(sk1Hex: p.inkSoft) : .white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(state == .ahead ? Color(sk1Hex: p.inkSoft).opacity(0.5) : .clear,
                                           lineWidth: 1.5))
            .background {
                if state == .next { Circle().fill(Hybrid.orange.opacity(0.25)).padding(-4) }
            }
            .accessibilityHidden(true)
    }

    private var fill: Color {
        switch state {
        case .done: return Hybrid.blueFill
        case .next: return Hybrid.orange
        case .ahead: return Hybrid.card(scheme)
        }
    }
}

// MARK: Keys and tabs

/// The bar over the tab bar: a tray of cream keys and the screen's one orange key.
struct TripBar<Keys: View>: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @ViewBuilder var keys: Keys

    var body: some View {
        HStack(spacing: 10) {
            SKKeyTray { keys }
            Button(action: action) {
                Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
            }
            .buttonStyle(.sk1Key(.orange, size: .large))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// The app's tabs.
enum AppTab: String, CaseIterable, Hashable {
    case home, list, map, restock, you

    var title: String {
        switch self {
        case .home: return "Home"
        case .list: return "List"
        case .map: return "Map"
        case .restock: return "Restock"
        case .you: return "You"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .list: return "list.bullet"
        case .map: return "map"
        case .restock: return "arrow.counterclockwise"
        case .you: return "person.crop.circle"
        }
    }
}

/// The tab bar, the same on every screen: the tab you're on in red, a red count on Restock when something's due.
struct AppTabBar: View {
    @Binding var selection: AppTab
    var badges: [AppTab: Int] = [:]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let active = tab == selection
                Button { selection = tab } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage).font(.system(size: 19, weight: .semibold))
                        Text(tab.title).font(.system(size: 11, weight: active ? .heavy : .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(alignment: .top) {
                        if let count = badges[tab], count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Hybrid.redFill))
                                .offset(x: 14, y: -3)
                        }
                    }
                    .foregroundStyle(active ? Hybrid.red(scheme) : Color(sk1Hex: SK1.palette(for: scheme).inkSoft))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(badges[tab].map { $0 > 0 ? "\(tab.title), \($0) due" : tab.title } ?? tab.title)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 6)
        .background(Hybrid.card(scheme).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Hybrid.line(scheme)).frame(height: 1) }
    }
}
