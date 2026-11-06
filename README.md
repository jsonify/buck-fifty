# Buck Fifty

A shopping list for iPhone that learns the order you walk through the store. Built for Costco runs and shared
between two people in real time. It uses the SK-1 look from [SK1Kit](https://github.com/jsonify/SK1Kit).

The plan is in the GitHub issues: the foundation (#1), shared real-time lists (#2), then learning the store order
from check-offs (#3), on-device zone guesses (#4), dead reckoning (#5), shelf-tag scanning (#6), Siri and the Watch
(#7) and wandering items (#8).

## What's here

- **Lists per store.** A new store called Costco starts with zones in walking order: entrance electronics, center
  tables, paper goods, pantry aisles, meat, the back cooler wall, frozen, bakery, then the rotisserie corner by the
  checkout. You can add, delete and reorder them (hold a zone in the Zones sheet and drag it, or use its arrows).
- **Items are remembered.** Each item keeps its zone, so it lands in the right place every time it's back on the
  list, and autocomplete suggests it as you type.
- **New items get a zone guess, on the phone.** Add something the store has never seen and Apple's on-device model
  (Foundation Models) picks its zone from your zone list, with a few items already in each zone as examples. It's
  guided generation, so it can only answer with one of your zones. No server, no network, no cost. It runs after the
  item is added and never holds up adding; on an iPhone or iOS without Apple Intelligence, or with it off, the item
  just stays unzoned. The row shows a **GUESSED** chip: tap it to fix the zone, or save to keep it. A zone you set by
  hand (even "No zone") is never replaced by a guess, and the guess is saved to the shared list, so only one phone
  guesses. Once you've bought the item, its learned position wins.
- **Drag items into place.** Hold an item and drag it onto another: it takes that one's place in the walk, and its
  zone. The drag sets its learned position, so the next trips start from where you put it rather than snapping back.
- **Trips.** Checking something off in the store starts a trip, or you tap **Start trip**. Every check-off is saved
  with its time on the trip, so the order you check things off is your route through the store. Unchecking during the trip removes that check-off, so a mis-tap teaches nothing. **Done** ends the trip
  and clears what you bought; a trip with no check-offs for 45 minutes ends on its own. Each person gets their own
  trip, so two people splitting up in the store don't mix their routes.
- **The list learns the store's order.** Your check-offs are the map. When a trip ends, each item you checked off
  gets a sample of where in the trip you grabbed it, by rank: the k-th of n check-offs is at k / (n − 1), from 0
  (entrance) to 1 (checkout). Its learned position moves 40% of the way toward each sample, so old trips fade; and
  when two trips in a row agree on a new place, it jumps there, so when the coffee moves the list catches up within
  two trips. A check-all at the checkout (three or more check-offs under 2 s apart at the end) is ignored, and a trip
  with fewer than two check-offs teaches nothing. The list is sorted by learned position; an item not learned yet
  goes by its zone's average, then its zone's place in the walking order, and items with no zone go last. Each item
  keeps its last 10 samples, and a time-based position too, to compare with the rank one on real trips. The logic is
  `RouteLearning` in `ShoppingCore`; `ListService.learn(from:)` applies it when a trip ends.

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

1. Build once with your team (`make install`, or Xcode). The project already has the iCloud (CloudKit) and Push
   Notifications entitlements, with the container `iCloud.com.jsonify.buckfifty`, and automatic signing registers
   the container and the App ID's capabilities the first time it signs the app.
2. Run a Debug build from Xcode on a phone signed in to iCloud, once, with the launch argument
   `-initializeCloudKitSchema` (Product > Scheme > Edit Scheme > Arguments), and again whenever the model gains
   attributes. This creates the record types in the development environment.
3. Before TestFlight or the App Store, open the [CloudKit console](https://icloud.developer.apple.com) and use
   **Deploy Schema Changes** to copy the schema to production.

Sharing needs two real iCloud accounts to try out: the simulator can't receive the pushes that make updates live.

## Layout

| Path | What |
|---|---|
| `App/` | The SwiftUI app: `BuckFiftyApp.swift`, `AppSupport.swift` (launch arguments, profile, fetches, demo data), `Sharing.swift` (the app model, the sharing sheet, accepting invitations), `ZoneGuesser.swift` (the on-device zone guess), `Views/` |
| `Packages/ShoppingKit` | The logic, as a Swift package: `ShoppingCore` (Foundation only: names, suggestions, list order, learning the route, zone-guess prompts, trip rules) and `ShoppingStore` (the Core Data model built in code, `Persistence` with its private and shared iCloud stores, `ListService` and `SharingService`) |
| `project.yml` | The Xcode project, for [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| `Makefile`, `Scripts/dist.sh` | Build, run in the Simulator, install on your iPhone (see below) |
| `Scripts/screenshots.sh` | Builds the app for the simulator, runs it on sample data and screenshots each screen |
| `Scripts/sk1-audit.sh` | Lists any native controls that have an SK-1 part (from SK1Kit) |

## Building

Needs Xcode 16.4 or later and XcodeGen (`brew install xcodegen`). `BuckFifty.xcodeproj` is generated from `project.yml` and isn't
tracked in git. Every `make` target regenerates it; run `xcodegen generate` yourself before opening it in Xcode, and
again after pulling. The app needs iOS 18 and signs with your team (`DEVELOPMENT_TEAM` in `project.yml`), as Meetball
does.

### Run it without Xcode

| Command | What it does |
|---|---|
| `make dist` | Build for the iOS Simulator into `dist/BuckFifty.app` |
| `make run` | Build and open it in the Simulator (the one already booted, or the newest iPhone) |
| `make demo` | The same, on the sample Costco list (`-demo`) instead of your own data |
| `make install` | Build Release for your iPhone (plugged in, or paired over Wi-Fi), install it and open it |
| `make test` | Run the package's tests (`swift test`) |
| `make screenshots` | Screenshot every screen in light and dark into `screenshots/`, as CI does |
| `make clean` | Delete `build/`, `dist/` and `screenshots/` |

With more than one iPhone connected, pick one with `DEVICE=<name> make install`. If a build fails, the errors are
printed and the full log is at `build/dist.log`. `Scripts/dist.sh --help` lists the flags behind these.

The demo store is in memory: `-demo` with `-demoScreen stores|list|add|trip|edit|zones` opens one screen, which is
what the screenshots use.

## CI

Every pull request runs one macOS job: the SK-1 audit and the package tests (warnings as errors). It then
builds the app for the iOS Simulator, runs it, and uploads screenshots of each screen in light and dark as the
`screenshots` artifact.
