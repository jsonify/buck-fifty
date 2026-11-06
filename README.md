# Buck Fifty

A shopping list for iPhone that learns the order you walk through the store. Built for Costco runs and shared
between two people in real time. It uses the SK-1 look from [SK1Kit](https://github.com/jsonify/SK1Kit).

The plan is in the GitHub issues: the foundation (#1), shared real-time lists (#2), then learning the store order
from check-offs (#3), on-device zone guesses (#4), dead reckoning (#5), shelf-tag scanning (#6), Siri and the Watch
(#7) and wandering items (#8).

## What's here

- **Lists per store.** A new store called Costco starts with zones in walking order: entrance electronics, center
  tables, paper goods, pantry aisles, meat, the back cooler wall, frozen, bakery, then the rotisserie corner by the
  checkout. You can add, delete and reorder them.
- **Items are remembered.** Each item keeps its zone, so it lands in the right place every time it's back on the
  list, and autocomplete suggests it as you type.
- **Trips.** Checking something off in the store starts a trip, or you tap **Start trip**. Every check-off is saved
  with its time on the trip, so the order you check things off is your route through the store, which #3 learns
  from. Unchecking during the trip removes that check-off, so a mis-tap teaches nothing. **Done** ends the trip
  and clears what you bought; a trip with no check-offs for 45 minutes ends on its own. Each person gets their own
  trip, so two people splitting up in the store don't mix their routes.

## Layout

| Path | What |
|---|---|
| `App/` | The SwiftUI app: `BuckFiftyApp.swift`, `AppSupport.swift` (launch arguments, profile, fetches, demo data), `Views/` |
| `Packages/ShoppingKit` | The logic, as a Swift package: `ShoppingCore` (Foundation only: names, suggestions, list order, trip rules; tests run on Linux) and `ShoppingStore` (the Core Data model, built in code, and `ListService`) |
| `project.yml` | The Xcode project, for [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| `Scripts/screenshots.sh` | Builds the app for the simulator, runs it on sample data and screenshots each screen |
| `Scripts/sk1-audit.sh` | Lists any native controls that have an SK-1 part (from SK1Kit) |

## Building

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open BuckFifty.xcodeproj
```

Choose your team under Signing & Capabilities to run it on a phone. The app needs iOS 26.

The package's tests:

```bash
swift test --package-path Packages/ShoppingKit
```

Run with `-demo` to use an in-memory store with a sample Costco list, and `-demoScreen stores|list|add|trip|edit|zones`
to open a particular screen. That's what the screenshots use.

## CI

Every pull request runs the package tests on Linux and macOS with warnings as errors, plus the SK-1 audit. It also
builds the app for the iOS Simulator, runs it, and uploads screenshots of each screen in light and dark as the
`screenshots` artifact.
