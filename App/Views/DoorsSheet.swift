import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// What the Map draws a store on: its floor plan drawing, or its zones laid out in walking order when it has none,
/// with the entrance and exit set on the Map (else the plan's own).
struct StoreDrawing {
    /// With the store's own doors.
    let plan: PlanDrawing
    /// With the drawing's doors, before any set on the Map.
    let base: PlanDrawing
    /// Whether it's a real floor plan, rather than the zones laid out in walking order.
    let isFloorPlan: Bool

    init(zoneNames: [String], store: Store) {
        if let plan = DefaultZones.plan(forZones: zoneNames) {
            base = plan
            isFloorPlan = true
        } else {
            // In and out at the bottom left, where the walk starts.
            let grid = WalkMap.layout(zoneNames)
            let door = grid.first.map { $0.rect.x + $0.rect.width / 2 } ?? 0.1
            base = PlanDrawing(aspect: 1.2, blocks: grid.map {
                PlanBlock($0.label, zone: $0.label, x: $0.rect.x, y: $0.rect.y, width: $0.rect.width,
                          height: $0.rect.height)
            }, entranceX: door, entranceY: 1)
            isFloorPlan = false
        }
        plan = base.withDoors(entrance: store.entrance, exit: store.exit)
    }
}

/// Where you come in and where you go out, set by tapping the store's map. The walk on the Map starts at the
/// entrance; with a floor plan, Order zones puts the zones in the order a short walk from the entrance to the exit
/// visits them.
struct DoorsSheet: View {
    enum Door: Hashable { case entrance, exit }

    @ObservedObject var store: Store
    let zones: [Zone]
    private let drawing: StoreDrawing
    @State private var door: Door = .entrance
    @State private var entrance: PlanPoint
    @State private var exit: PlanPoint
    @State private var confirmingOrder = false
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    init(store: Store, zones: [Zone]) {
        self.store = store
        self.zones = zones
        let drawing = StoreDrawing(zoneNames: zones.map(\.displayName), store: store)
        self.drawing = drawing
        _entrance = State(initialValue: drawing.plan.entrance)
        _exit = State(initialValue: drawing.plan.exit)
    }

    private var service: ListService { ListService(context: context) }

    var body: some View {
        SheetScaffold(title: "Entrance & exit",
                      detail: door == .entrance ? "TAP WHERE YOU COME IN" : "TAP WHERE YOU GO OUT") {
            SKSegmented(selection: $door, options: [
                SKSegmented<Door>.Option(.entrance, "Entrance"), SKSegmented<Door>.Option(.exit, "Exit"),
            ])
            DoorsMap(drawing: drawing, entrance: entrance, exit: exit, active: door) { point in
                switch door {
                case .entrance:
                    entrance = point
                    // Then where you go out.
                    door = .exit
                case .exit:
                    exit = point
                }
            }
            Text(hint)
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            Button("Reset") {
                entrance = drawing.base.entrance
                exit = drawing.base.exit
                door = .entrance
            }
            .buttonStyle(.sk1Key())
            .accessibilityHint("Puts the entrance and exit back where the floor plan has them")
            if drawing.isFloorPlan {
                Button("Order zones") { confirmingOrder = true }
                    .buttonStyle(.sk1Key())
                    .accessibilityHint("Puts the zones in walking order from the entrance to the exit")
            }
            Spacer()
            Button("Done") { save(orderingZones: false) }.buttonStyle(.sk1Key(.orange))
        }
        .confirmationDialog("Put the zones in walking order from this entrance to this exit?",
                            isPresented: $confirmingOrder, titleVisibility: .visible) {
            Button("Order zones") { save(orderingZones: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The shortest walk through the departments on the map. Where your trips found things still comes "
                 + "first; drag a thing on the list to put it right.")
        }
        .task {
            // The demo's screenshot shows the exit being set.
            if Launch.isDemo, Launch.demoScreen == "doors" { door = .exit }
        }
    }

    private var hint: String {
        let order = drawing.isFloorPlan
            ? " Order zones then walks the departments from one to the other; your trips refine it." : ""
        return "Tap Entrance, then the map where you come in; then Exit, and where you go out. The walk on the Map "
            + "starts at IN." + order
    }

    private func save(orderingZones: Bool) {
        // The plan's own doors aren't stored, so a later fix to the plan reaches the store.
        let isOwn = entrance == drawing.base.entrance && exit == drawing.base.exit
        service.setDoors(of: store, entrance: isOwn ? nil : entrance, exit: isOwn ? nil : exit)
        if orderingZones {
            let plan = drawing.plan.withDoors(entrance: entrance, exit: exit)
            service.orderZones(of: store, as: plan.walkingOrder(of: zones.map(\.displayName)))
        }
        do {
            try service.save()
        } catch {
            context.rollback()
            print("Buck Fifty: save failed: \(error)")
        }
        dismiss()
    }
}

/// The store's map, big, to tap the entrance or the exit on. A floor plan is turned upright to fill the phone.
private struct DoorsMap: View {
    let drawing: StoreDrawing
    let entrance: PlanPoint
    let exit: PlanPoint
    let active: DoorsSheet.Door
    let place: (PlanPoint) -> Void
    @Environment(\.colorScheme) private var scheme

    private var turned: Bool { drawing.isFloorPlan && drawing.plan.aspect > 1 }
    private var shown: PlanDrawing { turned ? drawing.plan.upright : drawing.plan }

    private func onScreen(_ point: PlanPoint) -> PlanPoint { turned ? point.upright : point }

    var body: some View {
        let p = SK1.palette(for: scheme)
        let ink = Color(sk1Hex: p.ink), soft = Color(sk1Hex: p.inkSoft), key = Color(sk1Hex: p.keyTop)
        let plan = shown
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for block in plan.blocks {
                        let r = block.rect.scaled(width: Double(size.width), height: Double(size.height))
                        let rect = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
                        let shape = Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3)
                        if block.zone != nil {
                            context.fill(shape, with: .color(key))
                            context.stroke(shape, with: .color(soft.opacity(0.6)), lineWidth: 1)
                        } else {
                            context.fill(shape, with: .color(soft.opacity(0.18)))
                        }
                        if let fontSize = ZoneMap.labelSize(block.label, width: r.width, height: r.height) {
                            context.draw(Text(block.label).font(.system(size: fontSize, weight: .semibold))
                                .foregroundStyle(block.zone == nil ? soft : ink), in: rect.insetBy(dx: 2, dy: 2))
                        }
                    }
                }
                DoorMarkers(entrance: onScreen(entrance), exit: onScreen(exit), size: size,
                            active: active == .entrance ? .entrance : .exit)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                guard size.width > 0, size.height > 0 else { return }
                let x = Double(tap.location.x / size.width), y = Double(tap.location.y / size.height)
                place((turned ? PlanPoint.fromUpright(x: x, y: y) : PlanPoint(x: x, y: y)).clamped)
            })
        }
        .aspectRatio(plan.aspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 540)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Store map. Tap where you come in, then where you go out.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

/// The entrance and the exit on a map, as IN and OUT tags (one IN · OUT tag when they're the same doors). The one
/// being set is orange.
struct DoorMarkers: View {
    enum Which { case entrance, exit, neither }

    /// In fractions of the map.
    let entrance: PlanPoint
    let exit: PlanPoint
    let size: CGSize
    var active: Which = .neither

    private var together: Bool {
        let dx = (entrance.x - exit.x) * Double(size.width), dy = (entrance.y - exit.y) * Double(size.height)
        return (dx * dx + dy * dy).squareRoot() < 30
    }

    var body: some View {
        if together {
            tag("IN · OUT", at: entrance, isActive: active != .neither)
        } else {
            tag("OUT", at: exit, isActive: active == .exit)
            tag("IN", at: entrance, isActive: active == .entrance)
        }
    }

    private func tag(_ text: String, at point: PlanPoint, isActive: Bool) -> some View {
        let width: CGFloat = text.count > 3 ? 52 : 32
        let height: CGFloat = 18
        // Kept inside the map, so a door on the wall isn't cut off.
        let x = min(max(CGFloat(point.x) * size.width, width / 2), max(size.width - width / 2, width / 2))
        let y = min(max(CGFloat(point.y) * size.height, height / 2), max(size.height - height / 2, height / 2))
        return Text(text)
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .background(Capsule().fill(isActive ? Hybrid.orange : Color(sk1Hex: 0x2B2A27)))
            .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1))
            .position(x: x, y: y)
            .accessibilityHidden(true)
    }
}
