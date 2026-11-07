import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// The zone of an item, as a full-width key: tap it to choose another on the store's floor plan or from the list.
struct ZoneField: View {
    @Binding var selection: Zone?
    let zones: [Zone]
    @State private var choosing = false

    var body: some View {
        Button { choosing = true } label: {
            HStack {
                Text(selection?.displayName ?? "No zone")
                Spacer(minLength: 8)
                Image(systemName: "map")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.sk1Key())
        .accessibilityLabel("Zone: \(selection?.displayName ?? "none"). Choose")
        .sheet(isPresented: $choosing) { ZoneChooserSheet(selection: $selection, zones: zones) }
        .task {
            // The demo's zone screenshot opens the chooser once the editor has finished appearing.
            guard Launch.isDemo, Launch.demoScreen == "zone" else { return }
            try? await Task.sleep(for: .seconds(1))
            choosing = true
        }
    }
}

/// Choosing a zone: tap it on the floor plan (when the store's zones have one) or pick it from the list, in walking
/// order. On the map a tap lights the zone and names it at the top (some blocks are too small to label), and tapping
/// it again or Done closes; in the list one tap chooses and closes.
struct ZoneChooserSheet: View {
    enum Mode: Hashable { case map, list }

    @Binding var selection: Zone?
    let zones: [Zone]
    private let plan: PlanDrawing?
    @State private var mode: Mode
    @Environment(\.dismiss) private var dismiss

    init(selection: Binding<Zone?>, zones: [Zone]) {
        _selection = selection
        self.zones = zones
        let plan = DefaultZones.plan(forZones: zones.map(\.displayName))
        self.plan = plan?.upright
        _mode = State(initialValue: plan == nil ? .list : .map)
    }

    var body: some View {
        SheetScaffold(title: "Zone", detail: (selection?.displayName ?? "No zone").uppercased()) {
            if plan != nil {
                SKSegmented(selection: $mode, options: [
                    SKSegmented<Mode>.Option(.map, "Map"), SKSegmented<Mode>.Option(.list, "List"),
                ])
            }
            if mode == .map, let plan {
                ZoneMap(plan: plan, zoneNames: zones.map(\.displayName), selected: selection?.displayName) { name in
                    let zone = zones.first { ItemName.normalized($0.displayName) == ItemName.normalized(name) }
                    if zone != nil, zone == selection {
                        dismiss()
                    } else {
                        selection = zone
                    }
                }
                Text("Tap the department it's in: the zone lights up and its name shows at the top. Tap it again or "
                     + "Done to keep it. Grey areas aren't zones; the black mark is the entrance.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                list
            }
        } actions: {
            Button("No zone") { choose(nil) }.buttonStyle(.sk1Key())
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.sk1Key(.orange))
        }
    }

    private var list: some View {
        SKGroup(caption: "Walking order") {
            ForEach(Array(zones.enumerated()), id: \.element.objectID) { index, zone in
                Button { choose(zone) } label: {
                    SKRow(title: zone.displayName, subtitle: "\(index + 1) of \(zones.count)") {
                        RadioMark(isOn: selection == zone)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == zone ? [.isSelected] : [])
            }
        }
    }

    /// Chooses `zone`, shows it for a moment, then closes.
    private func choose(_ zone: Zone?) {
        selection = zone
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            dismiss()
        }
    }
}

/// A radio button's mark: a ring, filled orange when chosen.
struct RadioMark: View {
    let isOn: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = SK1.palette(for: scheme)
        ZStack {
            Circle().stroke(Color(sk1Hex: p.inkSoft), lineWidth: 1.5)
            if isOn { Circle().fill(Color(sk1Hex: SK1.orange)).padding(4) }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// The store's floor plan with each department block tappable: tapping one chooses its zone. The chosen zone's
/// blocks are orange; places that aren't zones are grey.
struct ZoneMap: View {
    let plan: PlanDrawing
    let zoneNames: [String]
    let selected: String?
    let choose: (String) -> Void
    @Environment(\.colorScheme) private var scheme

    private var available: Set<String> { Set(zoneNames.map(ItemName.normalized)) }

    private func isAvailable(_ block: PlanBlock) -> Bool {
        block.zone.map { available.contains(ItemName.normalized($0)) } ?? false
    }

    private func isSelected(_ block: PlanBlock) -> Bool {
        guard let zone = block.zone, let selected else { return false }
        return ItemName.normalized(zone) == ItemName.normalized(selected)
    }

    var body: some View {
        let p = SK1.palette(for: scheme)
        let ink = Color(sk1Hex: p.ink), soft = Color(sk1Hex: p.inkSoft)
        let key = Color(sk1Hex: p.keyTop), orange = Color(sk1Hex: SK1.orange)
        GeometryReader { geo in
            let width = Double(geo.size.width), height = Double(geo.size.height)
            Canvas { context, _ in
                for block in plan.blocks {
                    let r = block.rect.scaled(width: width, height: height)
                    let rect = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
                    let shape = Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3)
                    let chosen = isSelected(block)
                    if chosen {
                        context.fill(shape, with: .color(orange))
                    } else if isAvailable(block) {
                        context.fill(shape, with: .color(key))
                        context.stroke(shape, with: .color(soft.opacity(0.6)), lineWidth: 1)
                    } else {
                        context.fill(shape, with: .color(soft.opacity(0.18)))
                    }
                    if r.width >= 22 && r.height >= 12 {
                        let label = Text(block.label)
                            .font(.system(size: r.width < 50 ? 8 : 9, weight: .semibold))
                            .foregroundStyle(chosen ? Color.white : (isAvailable(block) ? ink : soft))
                        context.draw(label, in: rect.insetBy(dx: 2, dy: 2))
                    }
                }
                let door = CGPoint(x: plan.entranceX * width, y: plan.entranceY * height)
                context.fill(Path(CGRect(x: door.x - 1, y: door.y - 7, width: 8, height: 14)), with: .color(ink))
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                guard let block = plan.block(atX: Double(tap.location.x), y: Double(tap.location.y),
                                             width: width, height: height),
                      isAvailable(block), let zone = block.zone else { return }
                choose(zone)
            })
        }
        .aspectRatio(plan.aspect, contentMode: .fit)
        // The whole store on one screen, rather than larger blocks that need scrolling.
        .frame(maxWidth: .infinity, maxHeight: 600)
        .accessibilityHidden(true)
    }
}
