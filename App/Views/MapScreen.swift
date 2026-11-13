import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// The Map tab (issue #25): the same trip as the List, on the store's floor plan. Zones you've done are blue, the next
/// one orange; each thing still to get is a pin with its walk number, the same number as on its row in the List; the
/// dashed line is the walk so far, to the orange dot where you are. Under the map, what's next uses the List's
/// headings and rows. A store with no floor plan drawing gets its zones laid out in walking order instead.
struct MapScreen: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Profile.self) private var profile
    @Environment(Navigator.self) private var navigator
    @FetchRequest private var entries: FetchedResults<ListEntry>
    @FetchRequest private var zones: FetchedResults<Zone>
    @FetchRequest private var items: FetchedResults<Item>
    @FetchRequest private var openTrips: FetchedResults<Trip>
    @State private var showingFloorPlan = false
    @State private var showingDoors = false
    @State private var editing: Editing?

    init(store: Store) {
        self.store = store
        _entries = FetchRequest(fetchRequest: Fetch.entries(in: store))
        _zones = FetchRequest(fetchRequest: Fetch.zones(in: store))
        _items = FetchRequest(fetchRequest: Fetch.items(in: store))
        _openTrips = FetchRequest(fetchRequest: Fetch.openTrips(in: store))
    }

    private var service: ListService { ListService(context: context) }
    private var actions: TripActions { TripActions(store: store, context: context, profile: profile) }
    private var trip: Trip? { service.activeTrip(among: Array(openTrips), for: profile.shopper) }

    var body: some View {
        let walk = WalkModel(entries: Array(entries), zones: Array(zones), items: Array(items))
        VStack(spacing: 10) {
            ScreenHeader(storeName: store.displayName, title: "Store map",
                         chooseStore: { navigator.choosingStore = true }) {
                StorePresencePill(store: store, openTrips: Array(openTrips))
            }
            walk.lcd(trip: trip, store: store, now: Date())
                .padding(.horizontal, 14)
            let map = WalkMap(walk: walk, store: store, inStore: trip != nil)
            WalkMapView(map: map)
                .contentShape(Rectangle())
                .onTapGesture { showingDoors = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Sets the entrance and exit")
                .padding(8)
                .frame(maxWidth: .infinity)
                .aspectRatio(CGFloat(map.aspect ?? 1.6), contentMode: .fit)
                .frame(maxHeight: 260)
                .background(SKWell { Color.clear })
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 14)
            ScrollView { upcoming(walk).padding(.horizontal, 14).padding(.vertical, 4) }
            TripBar(title: tripTitle, systemImage: trip == nil ? "cart" : "checkmark", action: toggleTrip) {
                Button { navigator.tab = .list } label: { Image(systemName: "list.bullet") }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("The list")
                Button { showingDoors = true } label: { Image(systemName: "door.left.hand.open") }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("Entrance and exit")
                if profile.mapsStore {
                    Button { showingFloorPlan = true } label: {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .buttonStyle(.sk1Key(isOn: StoreMapper.shared.isRecording(trip)))
                    .accessibilityLabel("Floor plan from mapped trips")
                }
            }
        }
        .padding(.top, 4)
        .sheet(isPresented: $showingFloorPlan) { FloorPlanSheet(store: store) }
        .sheet(isPresented: $showingDoors) { DoorsSheet(store: store, zones: Array(zones)) }
        .task {
            guard Launch.isDemo, Launch.demoScreen == "doors" else { return }
            try? await Task.sleep(for: .seconds(1))
            showingDoors = true
        }
        .sheet(item: $editing) { EditEntrySheet(entry: $0.entry, zones: Array(zones)) }
        .onAppear { actions.endLapsedTrips() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { actions.endLapsedTrips() }
        }
    }

    private var tripTitle: String {
        guard trip != nil else { return "Start trip" }
        let got = entries.filter { $0.isChecked && $0.checkedByID == profile.id }.count
        return "Done · \(got) got"
    }

    /// The stops still to do, from the next one on, with the List's headings and rows.
    @ViewBuilder private func upcoming(_ walk: WalkModel) -> some View {
        let stops = walk.walkStops.filter { $0.state != .done }
        let nextID = walk.next?.entry.entry.objectID
        VStack(alignment: .leading, spacing: 14) {
            if stops.isEmpty {
                Text(walk.rows.isEmpty ? "Nothing on the list yet." : "Everything's in the cart. Tap Done at the checkout.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(stops, id: \.id) { stop in
                VStack(alignment: .leading, spacing: 6) {
                    ZoneHeader(title: stop.state == .next ? "\(stop.title) · next" : stop.title,
                               count: "\(stop.left) left", state: stop.state)
                    ListCard {
                        ForEach(StopRow.rows(of: stop)) { item in
                            let entry = item.row.entry
                            ItemRow(name: entry.displayName, detail: entry.note, quantity: entry.quantity,
                                    isChecked: entry.isChecked, number: item.number, isNext: item.id == nextID,
                                    showsDivider: item.index > 0,
                                    toggle: trip == nil ? nil : { actions.toggle(entry) })
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = Editing(entry: entry) }
                                }
                        }
                    }
                }
            }
        }
    }

    private func toggleTrip() {
        if trip == nil {
            actions.start()
        } else {
            // What you got comes off the list; the rest stays for next time.
            _ = actions.finish(trip)
        }
    }
}

/// What the Map draws: the blocks (a floor plan's departments, or the zones in walking order), each zone's state, the
/// pins, and the walk so far.
struct WalkMap {
    struct Block {
        /// In fractions of the map: x across, y down.
        let rect: PlanRect
        let zone: Int?
        let label: String
    }

    /// One pin per zone with something left: its first walk number, and how many things are there.
    struct Pin: Identifiable {
        let number: Int
        let count: Int
        let zone: Int
        let isNext: Bool
        var id: Int { zone }
    }

    let blocks: [Block]
    /// Width over height, for a floor plan drawing; nil to fill the space (zones in walking order).
    let aspect: Double?
    /// The entrance and the exit, in fractions of the map.
    let entrance: PlanPoint
    let exit: PlanPoint
    let states: [Int: Walk.StopState]
    let pins: [Pin]
    /// The zones done so far, in walking order, then where you are: the walk's dashed line. Empty at home.
    let walked: [Int]
    let inStore: Bool

    init(walk: WalkModel, store: Store, inStore: Bool) {
        let names = walk.zoneNames
        func index(of zone: String?) -> Int? {
            guard let zone else { return nil }
            return names.firstIndex { ItemName.normalized($0) == ItemName.normalized(zone) }
        }
        // The plan as drawn, wide, to fill the card across the phone; the doors where the store has them.
        let drawing = StoreDrawing(zoneNames: names, store: store)
        if drawing.isFloorPlan {
            blocks = drawing.plan.blocks.map { Block(rect: $0.rect, zone: index(of: $0.zone), label: $0.label) }
            aspect = drawing.plan.aspect
        } else {
            blocks = Self.layout(names)
            aspect = nil
        }
        entrance = drawing.plan.entrance
        exit = drawing.plan.exit
        var states: [Int: Walk.StopState] = [:]
        for stop in walk.walkStops {
            guard case .zone(let zone) = stop.kind else { continue }
            switch (states[zone], stop.state) {
            case (_, .next), (.none, _): states[zone] = stop.state
            case (.some(.done), .ahead): states[zone] = .ahead
            default: break
            }
        }
        self.states = states
        let nextNumber = walk.next?.number
        var left: [Int: [Int]] = [:]
        for stop in walk.walkStops {
            guard case .zone(let zone) = stop.kind else { continue }
            for (row, number) in zip(stop.entries, stop.numbers) where !row.isChecked {
                if let number { left[zone, default: []].append(number) }
            }
        }
        pins = left.compactMap { zone, numbers in
            guard let first = numbers.min() else { return nil }
            return Pin(number: first, count: numbers.count, zone: zone,
                       isNext: nextNumber.map { numbers.contains($0) } ?? false)
        }
        .sorted { $0.number < $1.number }
        // The walk so far: every stop done before the next one, in order.
        var walked: [Int] = []
        if inStore {
            for stop in walk.walkStops {
                if stop.state != .done { break }
                if case .zone(let zone) = stop.kind, walked.last != zone { walked.append(zone) }
            }
        }
        self.walked = walked
        self.inStore = inStore
    }

    /// The zones in walking order as a grid, four across, snaking up from the door at the bottom left.
    static func layout(_ names: [String]) -> [Block] {
        let columns = 4
        let rows = max(1, Int((Double(names.count) / Double(columns)).rounded(.up)))
        let gap = 0.025
        let width = (1 - gap * Double(columns + 1)) / Double(columns)
        let height = (1 - gap * Double(rows + 1)) / Double(rows)
        return names.enumerated().map { index, name in
            let row = index / columns
            let place = index % columns
            let column = row % 2 == 0 ? place : columns - 1 - place
            let x = gap + Double(column) * (width + gap)
            let y = 1 - Double(row + 1) * (height + gap)
            return Block(rect: PlanRect(x: x, y: y, width: width, height: height), zone: index, label: name)
        }
    }

    /// A zone's biggest block, where its pins and the walk go.
    func anchor(of zone: Int) -> PlanRect? {
        blocks.filter { $0.zone == zone }.max { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }?.rect
    }
}

/// The map itself: blocks and the walk on a canvas, the pins and you on top.
struct WalkMapView: View {
    let map: WalkMap
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in draw(&context, size: size) }
                ForEach(map.pins) { pin in
                    if let point = center(of: pin.zone, size) {
                        ZonePin(pin: pin).position(x: point.x, y: point.y - 4)
                    }
                }
                DoorMarkers(entrance: map.entrance, exit: map.exit, size: size)
                if map.inStore {
                    youDot.position(you(size))
                }
            }
        }
        .aspectRatio(map.aspect.map { CGFloat($0) }, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let next = map.pins.first(where: \.isNext).map { "Next is stop \($0.number)." } ?? ""
        let left = map.pins.reduce(0) { $0 + $1.count }
        return "Store map. \(left) things to get in \(map.pins.count) zones. \(next) Tap to set the entrance and exit."
    }

    private var youDot: some View {
        Circle()
            .fill(Hybrid.orange)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .background(Circle().fill(Hybrid.orange.opacity(0.22)).padding(-7))
    }

    private func rect(_ r: PlanRect, _ size: CGSize) -> CGRect {
        let s = r.scaled(width: Double(size.width), height: Double(size.height))
        return CGRect(x: s.x, y: s.y, width: s.width, height: s.height)
    }

    private func center(of zone: Int, _ size: CGSize) -> CGPoint? {
        map.anchor(of: zone).map { r in let c = rect(r, size); return CGPoint(x: c.midX, y: c.midY) }
    }

    private func door(_ size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(map.entrance.x) * size.width, y: CGFloat(map.entrance.y) * size.height)
    }

    /// Where you are: the last zone done, or the door.
    private func you(_ size: CGSize) -> CGPoint {
        map.walked.last.flatMap { center(of: $0, size) } ?? door(size)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let p = SK1.palette(for: scheme)
        let ink = Color(sk1Hex: p.ink), soft = Color(sk1Hex: p.inkSoft)
        for block in map.blocks {
            let r = rect(block.rect, size)
            let shape = Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4)
            let state = block.zone.flatMap { map.states[$0] }
            switch state {
            case .some(.done):
                context.fill(shape, with: .color(Hybrid.blueFill.opacity(0.2)))
                context.stroke(shape, with: .color(Hybrid.blueFill.opacity(0.5)), lineWidth: 1)
            case .some(.next):
                context.fill(shape, with: .color(Hybrid.orange.opacity(0.22)))
                context.stroke(shape, with: .color(Hybrid.orange), lineWidth: 1.5)
            case .some(.ahead):
                context.fill(shape, with: .color(Hybrid.card(scheme)))
                context.stroke(shape, with: .color(soft.opacity(0.6)), lineWidth: 1)
            case .none:
                context.fill(shape, with: .color(soft.opacity(block.zone == nil ? 0.08 : 0.16)))
            }
            if let fontSize = ZoneMap.labelSize(block.label, width: Double(r.width), height: Double(r.height)) {
                let label = Text(block.label)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(state == nil ? soft : ink)
                context.draw(label, in: r.insetBy(dx: 2, dy: 2))
            }
        }
        // The walk so far, from the door through each zone done.
        if map.inStore {
            var walk = Path()
            walk.move(to: door(size))
            for zone in map.walked {
                if let point = center(of: zone, size) { walk.addLine(to: point) }
            }
            context.stroke(walk, with: .color(Hybrid.blueFill),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [2, 6]))
        }
    }
}

/// A zone's pin on the map: its first walk number, with how many things are there when it's more than one.
private struct ZonePin: View {
    let pin: WalkMap.Pin

    var body: some View {
        WalkBadge(number: pin.number, isNext: pin.isNext)
            .overlay(alignment: .topTrailing) {
                if pin.count > 1 {
                    Text("\(pin.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(pin.isNext ? Hybrid.orange : Hybrid.blueFill)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Capsule().fill(.white))
                        .overlay(Capsule().stroke(pin.isNext ? Hybrid.orange : Hybrid.blueFill, lineWidth: 1))
                        .offset(x: 8, y: -6)
                }
            }
            .accessibilityHidden(true)
    }
}
