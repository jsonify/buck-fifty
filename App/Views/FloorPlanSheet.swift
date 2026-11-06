import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// The floor plan mapping has built (issue #5): each item at its spot (the median of where it was checked off),
/// coloured by zone, with the last mapped trip's walk drawn over it. Turned so the aisles run up the screen, with the
/// door at the square.
struct FloorPlanSheet: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @FetchRequest private var items: FetchedResults<Item>
    @FetchRequest private var zones: FetchedResults<Zone>

    init(store: Store) {
        self.store = store
        _items = FetchRequest(fetchRequest: Fetch.items(in: store))
        _zones = FetchRequest(fetchRequest: Fetch.zones(in: store))
    }

    var body: some View {
        let plan = self.plan
        SheetScaffold(title: "Floor plan", detail: "\(plan.spots.count) ITEMS · \(plan.trips) TRIPS MAPPED") {
            if plan.spots.isEmpty && plan.path.isEmpty {
                Text("Nothing mapped yet. With Map the store on, tap Start trip at the door and check things off as "
                     + "you go: each one becomes a point here.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SKWell {
                    FloorCanvas(plan: plan, ink: ink, color: color(forZone:))
                        .frame(height: 380)
                        .padding(10)
                        .accessibilityElement()
                        .accessibilityLabel("Floor plan with \(plan.spots.count) items")
                }
                SKGroup(caption: "Zones", note: "The dashed line is your last mapped trip, from the door (the square).") {
                    ForEach(Array(zones.enumerated()), id: \.element.objectID) { index, zone in
                        let count = plan.spots.filter { $0.zone == index }.count
                        SKRow(title: zone.displayName, subtitle: count == 1 ? "1 item mapped" : "\(count) items mapped") {
                            Circle().fill(color(forZone: index)).frame(width: 14, height: 14)
                        }
                    }
                }
            }
        } actions: {
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.sk1Key(.orange))
        }
    }

    private var ink: Color { Color(sk1Hex: SK1.palette(for: scheme).ink) }

    /// A colour per zone, around the colour wheel in walking order; grey for no zone.
    private func color(forZone index: Int?) -> Color {
        guard let index, !zones.isEmpty else { return Color(sk1Hex: SK1.palette(for: scheme).inkSoft) }
        return Color(hue: 0.85 * Double(index) / Double(zones.count), saturation: 0.7,
                     brightness: scheme == .dark ? 0.95 : 0.8)
    }

    private var plan: FloorPlanModel {
        let service = ListService(context: context)
        let zoneList = Array(zones)
        let turn = store.gridHeading?.doubleValue ?? 0
        let spots = items.compactMap { item -> FloorPlanModel.Spot? in
            guard let point = service.spot(of: item) else { return nil }
            return FloorPlanModel.Spot(zone: item.storeZone.flatMap { zoneList.firstIndex(of: $0) },
                                       point: point.rotated(toHeading: turn))
        }
        let path = service.lastMappedTrip(at: store)?.floorPath.map { $0.rotated(toHeading: turn) } ?? []
        let trips = (store.trips ?? []).filter { $0.path != nil }.count
        return FloorPlanModel(spots: spots, path: path, trips: trips)
    }
}

/// What the floor plan draws, already turned to line up the aisles.
struct FloorPlanModel {
    struct Spot {
        let zone: Int?
        let point: FloorPoint
    }

    let spots: [Spot]
    let path: [FloorPoint]
    let trips: Int
}

/// The spots and the walk, scaled to fit, door at the square.
struct FloorCanvas: View {
    let plan: FloorPlanModel
    let ink: Color
    let color: (Int?) -> Color

    var body: some View {
        Canvas { context, size in
            let points = plan.spots.map(\.point) + plan.path + [FloorPoint.entrance]
            let margin = 2.0
            let minX = (points.map(\.x).min() ?? 0) - margin, maxX = (points.map(\.x).max() ?? 0) + margin
            let minY = (points.map(\.y).min() ?? 0) - margin, maxY = (points.map(\.y).max() ?? 0) + margin
            let scale = min(Double(size.width) / max(maxX - minX, 1), Double(size.height) / max(maxY - minY, 1))
            let dx = (Double(size.width) - (maxX - minX) * scale) / 2
            let dy = (Double(size.height) - (maxY - minY) * scale) / 2
            func place(_ p: FloorPoint) -> CGPoint {
                CGPoint(x: dx + (p.x - minX) * scale, y: Double(size.height) - dy - (p.y - minY) * scale)
            }

            if plan.path.count > 1 {
                var walk = Path()
                walk.addLines(plan.path.map(place))
                context.stroke(walk, with: .color(ink.opacity(0.45)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 4]))
            }
            let door = place(.entrance)
            context.fill(Path(CGRect(x: door.x - 5, y: door.y - 5, width: 10, height: 10)), with: .color(ink))
            for spot in plan.spots {
                let p = place(spot.point)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                             with: .color(color(spot.zone)))
            }
        }
    }
}
