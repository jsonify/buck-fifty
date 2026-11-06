import CoreData
import CoreMotion
import Foundation
import ShoppingCore
import ShoppingStore

/// Records a trip's walk by pedestrian dead reckoning (issue #5, experimental and off by default): distance from the
/// pedometer, heading from the compass (device motion against magnetic north), traced from the door. Each check-off
/// gets a point; an item whose spot has settled snaps the trip back onto it; at the end, the drift is spread back
/// along the walk between those known points and the checkout. Everything stays on the phone and in the shared list.
///
/// Only a trip started with the Start trip key is mapped: that's "start at the door", the origin. Used from the main
/// thread only (sensor callbacks hop to it).
final class StoreMapper {
    static let shared = StoreMapper()

    /// Whether this phone has what mapping needs: a pedometer and a compass.
    static var isAvailable: Bool {
        (CMPedometer.isDistanceAvailable() || CMPedometer.isStepCountingAvailable())
            && CMMotionManager.availableAttitudeReferenceFrames().contains(.xMagneticNorthZVertical)
    }

    /// Metres per step, for a phone that counts steps but doesn't estimate distance.
    private static let stepLength = 0.7
    /// How far into the store the first walk-in teaches the aisles' heading, for a store that doesn't know it yet.
    private static let gridLearningDistance = 12.0

    private(set) var trip: Trip?
    private var reckoning = DeadReckoning()
    /// The raw walk, point 0 at the door.
    private var raw: [FloorPoint] = [.entrance]
    /// Path indices whose true place is known (landmarks).
    private var anchors: [Int: FloorPoint] = [:]
    /// Each check-off of the trip, at its index in the walk.
    private var marks: [CheckOff: Int] = [:]
    /// Headings since the last pedometer update, and all of them while the aisles' heading is being learned.
    private var headings: [Double] = []
    private var walkInHeadings: [Double] = []
    private var lastHeading: Double?
    private var walked = 0.0
    private var learnedGrid: Double?

    private let pedometer = CMPedometer()
    private let motion = CMMotionManager()

    private init() {}

    func isRecording(_ trip: Trip?) -> Bool {
        trip != nil && self.trip == trip
    }

    /// Asks for Motion & Fitness access (the system prompt) by reading the last minute of steps.
    static func requestAccess() {
        guard CMPedometer.authorizationStatus() == .notDetermined else { return }
        CMPedometer().queryPedometerData(from: Date().addingTimeInterval(-60), to: Date()) { _, _ in }
    }

    /// Starts mapping `trip` from the door. `gridHeading` is the store's aisle heading, if known.
    func start(_ trip: Trip, gridHeading: Double?) {
        stopSensors()
        self.trip = trip
        reckoning = DeadReckoning(gridHeading: gridHeading)
        raw = [.entrance]
        anchors = [:]
        marks = [:]
        headings = []
        walkInHeadings = []
        lastHeading = nil
        walked = 0
        learnedGrid = nil

        motion.deviceMotionUpdateInterval = 0.2
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] data, _ in
            guard let heading = data?.heading, heading >= 0 else { return }
            self?.heard(heading: heading)
        }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data else { return }
            let total = data.distance?.doubleValue ?? data.numberOfSteps.doubleValue * StoreMapper.stepLength
            DispatchQueue.main.async { self?.walk(to: total) }
        }
    }

    /// The point to give a new check-off: where the walk is now (with the drift corrected so far), or the item's
    /// settled spot, which then corrects the walk.
    func mark(_ checkOff: CheckOff, landmark: FloorPoint?) -> FloorPoint? {
        guard trip != nil, checkOff.trip == trip else { return nil }
        let index = raw.count - 1
        marks[checkOff] = index
        if let landmark {
            anchors[index] = landmark
            return landmark
        }
        return raw[index] + PathCorrection.currentOffset(raw, anchors: anchors)
    }

    /// Stops mapping and returns the drift-corrected walk, each check-off's corrected point and, for a store that
    /// didn't know it, the aisles' heading learned on the walk in. `checkout` is the store's known checkout spot.
    func finish(checkout: FloorPoint?) -> (path: [FloorPoint], points: [CheckOff: FloorPoint], gridHeading: Double?) {
        stopSensors()
        var known = anchors
        if let checkout, raw.count > 1 { known[raw.count - 1] = checkout }
        let path = PathCorrection.corrected(raw, anchors: known)
        var points: [CheckOff: FloorPoint] = [:]
        for (checkOff, index) in marks where path.indices.contains(index) { points[checkOff] = path[index] }
        let grid = learnedGrid
        trip = nil
        return (path, points, grid)
    }

    /// Stops without keeping anything.
    func cancel() {
        stopSensors()
        trip = nil
    }

    // MARK: Sensors

    private func heard(heading: Double) {
        headings.append(heading)
        lastHeading = heading
    }

    private func walk(to total: Double) {
        guard trip != nil else { return }
        let distance = total - walked
        guard distance > 0, let heading = DeadReckoning.meanHeading(headings) ?? lastHeading else { return }
        walked = total
        headings.removeAll()
        if reckoning.gridHeading == nil {
            // The walk in from the door runs along an aisle: its heading is the store's grid.
            walkInHeadings.append(heading)
            if walked >= Self.gridLearningDistance, let grid = DeadReckoning.meanHeading(walkInHeadings) {
                reckoning.gridHeading = grid
                learnedGrid = grid
            }
        }
        raw.append(reckoning.walk(distance, heading: heading))
    }

    private func stopSensors() {
        pedometer.stopUpdates()
        motion.stopDeviceMotionUpdates()
    }
}
