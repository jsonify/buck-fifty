import CoreData
import Foundation
import ShoppingCore
import ShoppingStore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether zone guesses can run on this iPhone, and if not, why (shown on the Everything screen).
enum ZoneGuessStatus: Equatable {
    case ready
    case unavailable(String)

    var isReady: Bool { self == .ready }
}

/// Guesses an item's zone with Apple's on-device model (Foundation Models, issue #4): no server, no network, no cost.
/// Answers nil, and the item stays unzoned, where the model can't help (see `status`) or anything goes wrong.
enum ZoneGuesser {
    static var status: ZoneGuessStatus {
        if Launch.isDemo { return .unavailable("Zone guesses are off in the demo.") }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return OnDeviceZoneGuesser.status
        }
        return .unavailable("Zone guesses need iOS 26 with Apple Intelligence.")
        #else
        return .unavailable("Zone guesses need iOS 26 with Apple Intelligence.")
        #endif
    }

    static func guess(item: String, store: String, zones: [ZoneExamples]) async -> String? {
        guard !zones.isEmpty, status.isReady else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await OnDeviceZoneGuesser.guess(item: item, store: store, zones: zones)
        }
        #endif
        return nil
    }
}

/// Runs zone guesses in the background for a store's remembered items that have no zone and were never guessed or
/// set by hand: the ones just added, and any added before guesses existed or while the model wasn't ready. One at a
/// time, never blocking anything; a zone you set meanwhile always wins.
@MainActor
enum ZoneGuessing {
    private static var running: Set<NSManagedObjectID> = []

    /// How many of the store's items are waiting for a guess.
    static func waiting(in store: Store, context: NSManagedObjectContext) -> Int {
        let service = ListService(context: context)
        return (store.items ?? []).filter { service.needsZoneGuess($0) }.count
    }

    /// Whether guesses are running for the store now.
    static func isRunning(for store: Store) -> Bool { running.contains(store.objectID) }

    /// Guesses the zones of the store's items that need one (at most `limit` per run).
    static func guessMissing(in store: Store, context: NSManagedObjectContext, limit: Int = 40) {
        let key = store.objectID
        guard ZoneGuesser.status.isReady, !running.contains(key) else { return }
        let service = ListService(context: context)
        guard (store.items ?? []).contains(where: { service.needsZoneGuess($0) }) else { return }
        running.insert(key)
        Task {
            var tried = Set<Item>()
            while tried.count < limit,
                  let item = (store.items ?? []).filter({ service.needsZoneGuess($0) && !tried.contains($0) })
                      .min(by: { $0.displayName < $1.displayName }) {
                tried.insert(item)
                let answer = await ZoneGuesser.guess(item: item.displayName, store: store.displayName,
                                                     zones: service.zoneExamples(in: store))
                if service.applyZoneGuess(answer, to: item) != nil {
                    do { try service.save() } catch { print("Buck Fifty: saving a zone guess failed: \(error)") }
                    // Its milestone stays done once the guess is kept (and no longer marked guessed).
                    AppModel.shared.profile.markTried(Milestones.Try.guess)
                }
            }
            running.remove(key)
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private enum OnDeviceZoneGuesser {
    static var status: ZoneGuessStatus {
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return .ready }
        if case .unavailable(.appleIntelligenceNotEnabled) = availability {
            return .unavailable("Turn on Apple Intelligence (Settings, Apple Intelligence & Siri) for zone guesses.")
        }
        if case .unavailable(.modelNotReady) = availability {
            return .unavailable("Apple Intelligence is still getting ready on this iPhone. Guesses start once it is.")
        }
        if case .unavailable(.deviceNotEligible) = availability {
            return .unavailable("This iPhone doesn't support Apple Intelligence, so zones aren't guessed.")
        }
        return .unavailable("Apple Intelligence isn't available right now, so zones aren't guessed.")
    }

    static func guess(item: String, store: String, zones: [ZoneExamples]) async -> String? {
        // Guided generation: the answer's one field can only be one of the store's zone names.
        let zone = DynamicGenerationSchema(name: "Zone", anyOf: zones.map(\.name))
        let answer = DynamicGenerationSchema(name: "ZoneGuess", properties: [
            DynamicGenerationSchema.Property(name: "zone", description: "The zone the item is found in", schema: zone),
        ])
        do {
            let schema = try GenerationSchema(root: answer, dependencies: [])
            let session = LanguageModelSession(instructions: ZoneGuess.instructions)
            let prompt = ZoneGuess.prompt(item: item, store: store, zones: zones)
            let response = try await session.respond(to: prompt, schema: schema)
            return try response.content.value(String.self, forProperty: "zone")
        } catch {
            print("Buck Fifty: zone guess failed: \(error)")
            return nil
        }
    }
}
#endif
