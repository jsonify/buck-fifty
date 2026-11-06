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

- **Shared lists, live.** Tap the share key on a list to invite someone through Messages, Mail or a link. They
  tap the invitation and the list appears in their app. From then on, anything either of you adds, edits or checks
  off shows up on the other phone within seconds. On a shared list, rows say who added something ("Added by
  Partner") or whose cart it's in. The LCD says when the other person is in the store.

## Sharing: how it works

Lists sync through iCloud with Core Data's `NSPersistentCloudKitContainer`. There's no server of our own, and
nothing to pay beyond the Apple Developer Program membership the iCloud capability needs.

- Two stores: **private** (`Private.sqlite`, your iCloud private database) holds your own lists, and **shared**
  (`Shared.sqlite`, the shared database) holds lists other people shared with you.
- Sharing a store's list makes a `CKShare` of the `Store`, which takes everything hanging off it with it: zones,
  items, the list, trips and check-offs. That means the learned store order (#3) comes from both people's trips.
- Anything added to a shared list goes into the same store the list is in (`ListService`). Otherwise it would stay
  in your private database and the other person would never see it.
- Changes arrive as silent CloudKit pushes and are merged into the view context, and `@FetchRequest`s redraw.
  Offline changes are kept and sent when the phone is back online.
- Accepting an invitation goes through `SceneDelegate` (`App/Sharing.swift`) into the shared store.

### Setting up iCloud (once)

1. In Xcode, choose your team under **Signing & Capabilities**. The project already has the iCloud (CloudKit)
   and Push Notifications entitlements, with the container `iCloud.com.jsonify.buckfifty`. Xcode registers the
   container the first time it signs the app.
2. Run a Debug build on a phone signed in to iCloud, once, with the launch argument `-initializeCloudKitSchema`.
   This creates the record types in the development environment.
3. Before TestFlight or the App Store, open the [CloudKit console](https://icloud.developer.apple.com) and use
   **Deploy Schema Changes** to copy the schema to production.

Sharing needs two real iCloud accounts to try out: the simulator can't receive the pushes that make updates live.

## Layout

| Path | What |
|---|---|
| `App/` | The SwiftUI app: `BuckFiftyApp.swift`, `AppSupport.swift` (launch arguments, profile, fetches, demo data), `Sharing.swift` (the app model, the sharing sheet, accepting invitations), `Views/` |
| `Packages/ShoppingKit` | The logic, as a Swift package: `ShoppingCore` (Foundation only: names, suggestions, list order, trip rules) and `ShoppingStore` (the Core Data model built in code, `Persistence` with its private and shared iCloud stores, `ListService` and `SharingService`) |
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

Every pull request runs one macOS job: the SK-1 audit and the package tests (warnings as errors). It then
builds the app for the iOS Simulator, runs it, and uploads screenshots of each screen in light and dark as the
`screenshots` artifact.
