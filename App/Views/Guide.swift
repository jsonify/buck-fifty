import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

// The tour (on first launch, and from the You tab) and the guide (the You tab, and a tap on a milestone): every part of the
// app, what it does and every key. Both read `Guide.parts`, so when a feature changes, change its part here and both follow.

/// One part of the app, as the tour and the guide explain it.
struct GuidePart: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    /// One or two sentences: what it's for.
    let summary: String
    /// How it works, a point each.
    let points: [String]
    /// The keys that belong to it.
    var keys: [GuideKey] = []
}

/// A key and what it does.
struct GuideKey: Hashable {
    let systemImage: String
    let name: String
    let does: String
}

enum Guide {
    static let parts: [GuidePart] = [
        GuidePart(
            id: "home", title: "Home", systemImage: "house",
            summary: "Five tabs along the bottom: Home, List, Map, Restock and You. Each is about one store, named at "
                + "the top; tap its name to switch stores. Home is your next trip at a glance.",
            points: [
                "The store is the one you choose, else the one you're on a trip in, else the first. Tap the store's "
                    + "name at the top of any tab to choose another or add one. A teal lamp means someone is in that "
                    + "store now.",
                "Type in the field at the top to add something to the list, as on the List tab.",
                "The LCD says when the next trip probably is and how many things are on the list. The strip under it "
                    + "is this week: a filled cell for each day you shopped, NEXT on the day you'll probably go.",
                "Your list shows the first few things in store order, with the stop each is at. All opens the List "
                    + "tab.",
                "Due before the next trip: a card for each thing you'll run out of. Add puts it on the list; Add all "
                    + "does them all.",
                "New at says when Buck Fifty has learned enough to switch something on. Coming up shows what it "
                    + "learns next, or your level, as set on the You tab. See Milestones.",
                "Last 30 days counts this store's trips, the things bought, the average trip and the last one.",
            ],
            keys: [
                GuideKey(systemImage: "cart", name: "Start trip",
                         does: "Starts a trip at the door and opens the list. Says Back to the trip while you're on one."),
                GuideKey(systemImage: "person.badge.plus", name: "Share",
                         does: "Invites someone to this store's list. It stays lit once the list is shared."),
                GuideKey(systemImage: "person.crop.circle", name: "You",
                         does: "The last tab: your name, how milestones show, the tour, the guide and Map the store."),
            ]),
        GuidePart(
            id: "list", title: "The list", systemImage: "list.bullet",
            summary: "Each store has its own list. At home it's a plain list in your own order; in the store it "
                + "sorts itself into the order you walk the store: a stop for each zone, on a rail from the door to "
                + "the checkout.",
            points: [
                "Type in the field to add something; Return adds it and leaves the keyboard up for the next one. "
                    + "Things the store remembers come up as you type, with their zone: tap one to add it. Adding "
                    + "something that's already on the list adds one more (×2).",
                "Past items, over the list, is everything you've bought here before: what you buy most, what's "
                    + "running low, the last trip, or A to Z, with a find field. Tap things to put them on the list. "
                    + "They stay off the list itself, so each trip starts with a clean list.",
                "At home the list is in your order: new things go at the bottom, and you hold one and drag it onto "
                    + "another to move it there. Start a trip (or check something off) and it sorts itself by "
                    + "where things are in the store.",
                "Tap a row to check it off. Hold a row to edit its name, zone, spot, how many and a note, or to "
                    + "remove it.",
                "Every row in the walk has a number: the order you'll pick it up. The numbers stay put as you check "
                    + "things off, so 7 is still 7 at the end of the trip. The next one is orange; done stops turn "
                    + "blue on the rail.",
                "Look for it, at the top, holds things that move around the store, with where they've been seen. "
                    + "They have no number.",
                "In the store, hold an item and drag it onto another: it takes that one's place in the walk, and its "
                    + "zone. The list remembers where you put it.",
                "Each zone is one stop, in the order your walk reaches it, so a zone never shows up twice. The only "
                    + "numbers on the list are the walk numbers on the right; the rail's dots turn blue with a tick as "
                    + "each stop is done.",
                "The switch over the list shows it My order at home, By zone in the store (stops on the rail, with "
                    + "walk numbers), or A to Z (one card by name, each row saying its zone, no numbers and no "
                    + "dragging). Your phone remembers which.",
                "On a shared list, rows say who added them, or whose cart they're in.",
                "The LCD says At home or In the store and how many things are left. In the store it names the next "
                    + "thing to get, and its strip has a cell per stop: full once done, half for the next one.",
            ],
            keys: [
                GuideKey(systemImage: "clock.arrow.circlepath", name: "Past items",
                         does: "Everything you've bought here before, to tap onto the list."),
                GuideKey(systemImage: "square.stack.3d.up", name: "Zones",
                         does: "The store's zones in walking order, to reorder, add, delete or start from a layout."),
                GuideKey(systemImage: "tray.full", name: "Everything",
                         does: "Your last trip and every item the store remembers."),
                GuideKey(systemImage: "map", name: "Floor plan",
                         does: "Where things are, from mapped trips. Only there with Map the store on."),
                GuideKey(systemImage: "person.badge.plus", name: "Share",
                         does: "Invites someone to the list. It stays lit once the list is shared."),
                GuideKey(systemImage: "flag.checkered", name: "Start trip / Done",
                         does: "Starts a trip at the door; Done ends it, takes what you bought off the list and asks about "
                             + "what you didn't get."),
            ]),
        GuidePart(
            id: "storemap", title: "The Map tab", systemImage: "map.fill",
            summary: "The same trip as the list, drawn on the store: each zone where it is, with a pin for what's "
                + "left there.",
            points: [
                "Zones come from the store's floor plan when it has one (the Aurora Village layout does), else they're "
                    + "laid out in walking order from the door.",
                "Blue zones are done, the orange one is next, the rest are still ahead. The dashed blue line is the "
                    + "walk so far, from the door; the orange dot is about where you are.",
                "Each zone with something left has a pin: the walk number of the first thing there, the same number "
                    + "as on the list, with how many things are there when it's more than one. Under the map, the stops "
                    + "still to do and what's at them: tap one to check it off.",
                "It works without Map the store. With it on, the floor plan key shows where things really are, from "
                    + "your mapped trips.",
            ],
            keys: [
                GuideKey(systemImage: "list.bullet", name: "List", does: "Opens the List tab."),
                GuideKey(systemImage: "map", name: "Floor plan",
                         does: "Where things are, from mapped trips. Only there with Map the store on."),
                GuideKey(systemImage: "flag.checkered", name: "Start trip / Done",
                         does: "The same trip key as on the list."),
            ]),
        GuidePart(
            id: "restock", title: "Restock", systemImage: "checklist",
            summary: "Restock, its own tab, is the checklist for your next trip: everything the store remembers, with "
                + "what you'll run out of first.",
            points: [
                "The LCD says when the next trip is and how many things are due. The tab's badge says it too.",
                "Every check-off is a purchase with a date, so each item has a rhythm: the usual days between buying "
                    + "it. The store has one too, which says when the next trip is.",
                "Before the next trip: what will run out before then (DUE), or should have already (LATE). Running "
                    + "low soon: due the trip after next. Staples: bought on half the trips or more. Now and then: the "
                    + "rest.",
                "Tap a row to tick it onto the list, and again to take it off. Add N due puts everything due on the "
                    + "list. When nothing's left to add, the key opens the list.",
                "It needs two purchases of something to know its rhythm. Purchases count by day, so two people "
                    + "splitting up in the store count once.",
            ]),
        GuidePart(
            id: "zones", title: "Zones", systemImage: "square.stack.3d.up",
            summary: "Zones are the parts of the store in the order you walk them. Each item remembers its zone.",
            points: [
                "The Zones key lists them front door first. Hold one and drag it, or use its arrows; add or delete "
                    + "zones there too.",
                "Start from a layout replaces them in one go: the Aurora Village Costco from its floor plan, a typical "
                    + "Costco, or any store. Zones with the same name keep their items.",
                "In an item's editor, the zone key opens the chooser: on the Aurora Village layout, tap a department "
                    + "on the floor plan; on any store, pick from the list.",
                "Something the store has never seen gets its zone guessed on the iPhone by Apple Intelligence, from "
                    + "your zones and what's in them. It's marked GUESSED until you save or fix it. No network, no "
                    + "cost; without Apple Intelligence it stays unzoned.",
                "A zone you set by hand, even No zone, is never replaced by a guess.",
            ]),
        GuidePart(
            id: "trips", title: "Trips", systemImage: "cart",
            summary: "A trip is one person's visit to the store. The order you check things off is your route.",
            points: [
                "Tap Start trip at the door, or just check something off: that starts one too.",
                "Every check-off is saved with its time. Uncheck something during the trip and that check-off is "
                    + "forgotten, so a mis-tap teaches nothing.",
                "Done ends the trip: what you bought comes off the list (the store still remembers it, in Past items) "
                    + "and Everything opens so you can review the trip. What you didn't get stays on the list for next "
                    + "time, unless you drop it there.",
                "A trip with no check-offs for 45 minutes ends by itself.",
                "Each person has their own trip, so two people splitting up don't mix their routes.",
            ]),
        GuidePart(
            id: "learning", title: "Learning the store", systemImage: "figure.walk",
            summary: "Your check-offs are the map. After every trip the list moves closer to the order you actually "
                + "walk.",
            points: [
                "Where in the trip you grabbed each thing becomes a position from the entrance (0) to the checkout (1): "
                    + "the 3rd of 5 check-offs is at 0.5.",
                "Each item moves 40% of the way toward each new position, so old trips fade. When two trips in a row "
                    + "agree on a new place, it jumps there: if the coffee moves, the list catches up in two trips.",
                "A burst of check-offs at the checkout (three or more under 2 seconds apart) is ignored, and a trip "
                    + "with fewer than two check-offs teaches nothing.",
                "Not learned yet, an item goes by its zone's average, then its zone's place in the walking order. "
                    + "Items with no zone go last.",
                "Some things never stay put, like seasonal and treasure-hunt finds. When three or more trips find "
                    + "something all over the store, it moves to Look for it at the top of the list, with where it's "
                    + "been seen (anywhere from 20% to 75% of the way in, last at 40%). Once three trips in a row "
                    + "agree, it goes back into the walk.",
                "Spot, in an item's editor, decides it yourself: Moves around keeps it under Look for it, Fixed spot "
                    + "keeps it in the walk, Learn it goes by the trips. It's shared like the rest of the list.",
            ]),
        GuidePart(
            id: "everything", title: "Everything", systemImage: "tray.full",
            summary: "Everything is your last trip and every item the store remembers. It opens by itself after Done.",
            points: [
                "Opened by Done, it starts with what the trip didn't get: it stays on the list for next time, or Drop "
                    + "(or Drop all) takes it off so the next list starts clean.",
                "The last trip shows what you bought, in the order you checked it off.",
                "Under it, every item the store remembers, in walking order under its zone, with where in the walk "
                    + "it's grabbed.",
                "Tap one to set its zone, rename it, put it back on the list or forget it. Hold and drag one onto "
                    + "another to move it in the walk.",
                "Guess zones asks Apple Intelligence for every item without one.",
            ]),
        GuidePart(
            id: "sharing", title: "Sharing", systemImage: "person.2",
            summary: "Share a store's list with someone and you both see every change within seconds.",
            points: [
                "The share key on a list invites someone by Messages, Mail or a link. They tap it and the list appears "
                    + "in their app.",
                "Everything about the store is shared: zones, items, the list, trips and what's been learned, so both "
                    + "people's trips teach the order.",
                "Rows say who added something or whose cart it's in; the LCD and the home screen say when the other "
                    + "person is in the store.",
                "It goes through iCloud: no server, no cost. Changes made offline are sent when you're back online.",
                "Your name, on the You tab, is what they see.",
            ]),
        GuidePart(
            id: "map", title: "Map the store", systemImage: "map",
            summary: "Experimental, and off until you turn it on: your steps and the compass trace your walk, and every "
                + "check-off becomes a point on a floor plan.",
            points: [
                "Turn on Map the store on the You tab, then tap Start trip at the door and keep the app open while you "
                    + "shop.",
                "Steel shelves bend the compass, so headings snap to the aisles, items that have settled correct where "
                    + "you are, and the walk's end is pinned to the checkout.",
                "The floor plan key on the list shows items coloured by zone, with your last walk over them. After about ten "
                    + "trips it's worth a look.",
                "It asks for Motion & Fitness access. The walk stays on your phone and in your shared list.",
            ]),
        GuidePart(
            id: "milestones", title: "Milestones", systemImage: "flag.2.crossed",
            summary: "Buck Fifty gets smarter as you shop, so some of it only switches on after a few trips. "
                + "Milestones shows what it has learned, what's next and how soon, and features to try.",
            points: [
                "Learning, for each store: the walk after one trip, the next-trip day after two days shopped, what's "
                    + "running low once something's been bought twice, staples after three days, Look for it after "
                    + "three trips, guessed zones, and the floor plan after ten mapped trips.",
                "Each says how far along it is (2/3) and what it's waiting for. They count the store's trips, so "
                    + "they're the same on every phone it's shared with.",
                "Try it: features that are there already, like Restock, dragging an item into place, Everything, an "
                    + "item's spot, a zone layout, sharing and Map the store. Each is ticked the first time you use "
                    + "it on this phone.",
                "Tap a milestone for how it works, here in the guide.",
                "On the You tab, choose how home shows them: Checklist, the next three with how far along each is; or "
                    + "Levels, a level from New in town to Knows the store that goes up as they're done.",
                "When one switches on, home says so once, in New at.",
            ],
            keys: [
                GuideKey(systemImage: "flag.2.crossed", name: "All milestones",
                         does: "Every milestone for a store, on home under Coming up and on the You tab."),
                GuideKey(systemImage: "checkmark", name: "Got it",
                         does: "Puts away what just switched on, on home."),
            ]),
    ]
}

// MARK: The tour

/// The tour: a welcome that asks your name, a page for each part of the app, then a last page that starts your first
/// store. Shown once on first launch, and again from the You tab.
struct TourSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Profile.self) private var profile
    @FetchRequest(fetchRequest: Fetch.stores()) private var stores: FetchedResults<Store>
    @State private var page = 0
    @State private var storeName = "Costco"

    private var lastPage: Int { Guide.parts.count + 1 }

    var body: some View {
        VStack(spacing: 0) {
            SKStatusStrip(title: "How Buck Fifty works", detail: "\(page + 1) OF \(lastPage + 1)")
                .padding(.horizontal, 16)
                .padding(.top, 16)
            TabView(selection: $page) {
                welcome.tag(0)
                ForEach(Array(Guide.parts.enumerated()), id: \.element.id) { index, part in
                    TourPage(part: part).tag(index + 1)
                }
                finish.tag(lastPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            SKGroove()
            HStack(spacing: 8) {
                if page < lastPage {
                    Button("Skip", action: close).buttonStyle(.sk1Key())
                }
                Spacer()
                if page > 0 {
                    Button("Back") { turn(to: page - 1) }.buttonStyle(.sk1Key())
                }
                Button(page == lastPage ? "Start" : "Next") {
                    if page == lastPage { start() } else { turn(to: page + 1) }
                }
                .buttonStyle(.sk1Key(.orange))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .sk1Chassis()
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        @Bindable var you = profile
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TourTitle(systemImage: "cart", title: "Buck Fifty")
                Text("A shopping list that learns the order you walk through the store, and what you'll need before "
                     + "you go. Shared with someone, it changes on both phones as you shop.")
                    .sk1Ink()
                    .fixedSize(horizontal: false, vertical: true)
                Text("This tour has a page for every part of the app. Swipe, or use Next. It's always on the You tab, "
                     + "with the guide.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
                CaptionedField(caption: "Your name",
                               note: "Shown next to what you add and check off, to anyone you share a list with.") {
                    SKTextField("Your name", text: $you.name, prompt: "Jason")
                        .textContentType(.givenName)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var finish: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TourTitle(systemImage: "flag.checkered", title: "Your first trip")
                Text("Add a few things, go shopping, and check each one off as it goes in the cart. After a couple of "
                     + "trips the list is in your walking order, and Restock knows what you'll need.")
                    .sk1Ink()
                    .fixedSize(horizontal: false, vertical: true)
                if stores.isEmpty {
                    CaptionedField(caption: "Start with a store",
                                   note: "A Costco starts with its zones in walking order. You can change them.") {
                        SKTextField("Store name", text: $storeName, prompt: "Costco")
                            .onSubmit(start)
                    }
                } else {
                    Text("Tap Start to go to your lists.").sk1Hint()
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func turn(to newPage: Int) {
        withAnimation { page = min(max(newPage, 0), lastPage) }
    }

    /// Starts the first store (if there's none and it has a name), then closes.
    private func start() {
        if stores.isEmpty, !ItemName.cleaned(storeName).isEmpty {
            let service = ListService(context: context)
            service.createStore(named: storeName)
            try? service.save()
        }
        close()
    }

    private func close() {
        profile.hasSeenTour = true
        dismiss()
    }
}

/// A tour page's title, its symbol in a tray beside it.
private struct TourTitle: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            SKWell {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .sk1Ink()
            }
            .frame(width: 44, height: 44)
            Text(title)
                .font(.title2.weight(.semibold))
                .sk1Ink()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One part of the app as a tour page: what it's for, a picture of it, how it works and its keys.
private struct TourPage: View {
    let part: GuidePart

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TourTitle(systemImage: part.systemImage, title: part.title)
                Text(part.summary)
                    .sk1Ink()
                    .fixedSize(horizontal: false, vertical: true)
                TourPicture(id: part.id)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                GuidePoints(part: part)
            }
            .padding(16)
        }
    }
}

/// A picture of a part, made of the real parts with sample numbers.
private struct TourPicture: View {
    let id: String

    var body: some View {
        switch id {
        case "home":
            VStack(spacing: 10) {
                TripLCD(label: "Next trip tomorrow", main: "Costco · on the list", number: 14, unit: "items",
                        strip: weekStrip, legend: ["Last 3 days ago", "Every 4 days"])
                ListCard {
                    ItemRow(name: "Bananas", detail: "Produce", isChecked: false, number: 1, isNext: true, toggle: {})
                    ItemRow(name: "Eggs", detail: "Dairy & center coolers", quantity: 2, isChecked: false, number: 2,
                            showsDivider: true, toggle: {})
                }
            }
        case "list":
            VStack(alignment: .leading, spacing: 6) {
                ZoneHeader(title: "Dairy & center coolers", count: "2 of 3", state: .next)
                ListCard {
                    ItemRow(name: "Eggs", quantity: 2, isChecked: true, number: 6, toggle: {})
                    ItemRow(name: "Greek yogurt", detail: "Added by Sam", detailTone: .info, isChecked: false,
                            number: 7, isNext: true, showsDivider: true, toggle: {})
                    ItemRow(name: "Kirkland pesto", isChecked: false, number: 8, showsDivider: true,
                            accessory: AnyView(UrgencyTag(text: "GUESSED")), toggle: {})
                }
            }
        case "storemap":
            VStack(spacing: 10) {
                TripLCD(label: "In the store · 12 min", main: "Next 7 · Greek yogurt", number: 5, unit: "left",
                        strip: [StripCell(fill: .full), StripCell(fill: .full), StripCell(fill: .half, marked: true),
                                StripCell(fill: .empty), StripCell(fill: .empty)],
                        legend: ["Entry", "Dairy", "Exit"])
                HStack(spacing: 8) {
                    WalkBadge(number: 6, isNext: false)
                    WalkBadge(number: 7, isNext: true)
                    WalkBadge(number: 8, isNext: false)
                    Spacer()
                }
            }
        case "restock":
            VStack(alignment: .leading, spacing: 6) {
                ZoneHeader(title: "Before the next trip", count: "3", state: .next)
                ListCard {
                    ItemRow(name: "Milk", detail: "On the list · Every week · last 7 days ago", isChecked: true,
                            accessory: AnyView(UrgencyTag(text: "DUE")), toggle: {})
                    ItemRow(name: "Butter", detail: "Every 2 weeks · last 14 days ago", isChecked: false,
                            showsDivider: true, accessory: AnyView(UrgencyTag(text: "DUE")), toggle: {})
                    ItemRow(name: "Dish soap", detail: "Every 3 weeks · last 33 days ago", isChecked: false,
                            showsDivider: true, accessory: AnyView(UrgencyTag(text: "LATE", late: true)), toggle: {})
                }
            }
        case "zones":
            SKGroup(caption: "Walking order") {
                SKRow(title: "Produce", subtitle: "12 items") { SKChip("1", minWidth: 28) }
                SKRow(title: "Bakery", subtitle: "4 items") { SKChip("2", minWidth: 28) }
                SKRow(title: "Meat", subtitle: "9 items") { SKChip("3", minWidth: 28) }
            }
        case "trips":
            VStack(spacing: 10) {
                TripLCD(label: "In the store · 18 min", main: "Next 4 · Rice", number: 11, unit: "left",
                        strip: [StripCell(fill: .full), StripCell(fill: .half, marked: true), StripCell(fill: .empty),
                                StripCell(fill: .empty)],
                        legend: ["Entry", "Pantry", "Exit"])
                ListCard {
                    ItemRow(name: "Paper towels", isChecked: true, number: 1, toggle: {})
                    ItemRow(name: "Olive oil", isChecked: true, number: 2, showsDivider: true, toggle: {})
                }
            }
        case "learning":
            VStack(spacing: 10) {
                SKGroup(caption: "Last trip, in the order checked off") {
                    SKRow(title: "Bananas", subtitle: "1st of 5") { SKChip("0.00", minWidth: 52) }
                    SKRow(title: "Olive oil", subtitle: "3rd of 5") { SKChip("0.50", minWidth: 52) }
                    SKRow(title: "Rotisserie chicken", subtitle: "5th of 5") { SKChip("1.00", minWidth: 52) }
                }
                ListCard {
                    ItemRow(name: "Advent calendar", detail: "Look for it · seen from 15% to 80% of the way in",
                            detailTone: .alert, isChecked: false, toggle: {})
                }
            }
        case "sharing":
            VStack(alignment: .leading, spacing: 10) {
                PresencePill(text: "Sam in the store", lit: true)
                TripLCD(label: "At home · Costco", main: "4 stops in the walk", number: 9, unit: "on list")
            }
        case "milestones":
            VStack(spacing: 10) {
                LevelMeter(level: Milestones.level(done: 6, of: 14), total: 14)
                SKGroup(caption: "Coming up · 6 of 14") {
                    if let next = Milestones.all(MilestoneFacts(teachingTrips: 2, tripDays: 2))
                        .first(where: { $0.id == "lookForIt" }) {
                        MilestoneRow(milestone: next)
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    /// A sample week: shopped three days ago, the next trip tomorrow.
    private var weekStrip: [StripCell] {
        (-3...3).map { offset in
            switch offset {
            case -3: return StripCell(fill: .full)
            case 1: return StripCell(fill: .empty, marked: true, text: "NEXT")
            default: return StripCell(fill: .empty)
            }
        }
    }
}

/// A part's points ("How it works") and its keys, in trays.
private struct GuidePoints: View {
    let part: GuidePart

    var body: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
            SKGroup(caption: "How it works") {
                ForEach(part.points, id: \.self) { point in
                    Text(point)
                        .font(.subheadline)
                        .sk1Ink()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
            }
            if !part.keys.isEmpty {
                SKGroup(caption: "Keys") {
                    ForEach(part.keys, id: \.self) { key in
                        SKRow(title: key.name, subtitle: key.does) {
                            Image(systemName: key.systemImage)
                                .font(.system(size: 14, weight: .medium))
                                .sk1Ink()
                                .frame(width: 30)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: The guide

/// The guide: every part of the app, to look things up. Contents at the top jump to a part.
struct GuideSheet: View {
    /// The part to open at (a `GuidePart.id`), or nil for the top.
    var startAt: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                        SKStatusStrip(title: "Guide", detail: "\(Guide.parts.count) PARTS")
                        Text("Everything Buck Fifty does and every key. Tap a part to jump to it.")
                            .sk1Hint()
                            .fixedSize(horizontal: false, vertical: true)
                        SKGroup(caption: "Contents") {
                            ForEach(Guide.parts) { part in
                                Button { proxy.scrollTo(part.id, anchor: .top) } label: {
                                    SKRow(title: part.title) {
                                        Image(systemName: part.systemImage)
                                            .font(.system(size: 14, weight: .medium))
                                            .sk1Ink(soft: true)
                                            .frame(width: 30)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        ForEach(Guide.parts) { part in
                            VStack(alignment: .leading, spacing: 12) {
                                TourTitle(systemImage: part.systemImage, title: part.title)
                                Text(part.summary)
                                    .sk1Ink()
                                    .fixedSize(horizontal: false, vertical: true)
                                GuidePoints(part: part)
                            }
                            .padding(.top, 8)
                            .id(part.id)
                        }
                    }
                    .padding(SK1.Metrics.paneMargin)
                }
                .onAppear {
                    guard let startAt else { return }
                    // After the first layout, so the part has a place to scroll to.
                    DispatchQueue.main.async { proxy.scrollTo(startAt, anchor: .top) }
                }
            }
            SKGroove()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.sk1Key(.orange))
            }
            .padding(.horizontal, SK1.Metrics.paneMargin)
            .padding(.vertical, 12)
        }
        .sk1Chassis()
    }
}
