import Foundation
import ShoppingCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Guesses a brand-new item's zone with Apple's on-device model (Foundation Models, issue #4): no server, no network,
/// no cost. Answers nil, and the item stays unzoned, where the model can't help: an iPhone or iOS without Apple
/// Intelligence, Apple Intelligence turned off or still downloading, the demo, or any error.
enum ZoneGuesser {
    static func guess(item: String, store: String, zones: [ZoneExamples]) async -> String? {
        guard !zones.isEmpty, !Launch.isDemo else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await OnDeviceZoneGuesser.guess(item: item, store: store, zones: zones)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private enum OnDeviceZoneGuesser {
    static func guess(item: String, store: String, zones: [ZoneExamples]) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
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
