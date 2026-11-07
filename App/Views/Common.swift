import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore

/// Text in the palette's ink, or its soft ink.
struct InkStyle: ViewModifier {
    var soft = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let p = SK1.palette(for: scheme)
        content.foregroundStyle(Color(sk1Hex: soft ? p.inkSoft : p.ink))
    }
}

extension View {
    func sk1Ink(soft: Bool = false) -> some View { modifier(InkStyle(soft: soft)) }
}

/// A sheet on the chassis: a status strip with its title, the content in a scrolling pane, and the action keys under
/// a groove (Cancel cream, the action orange).
struct SheetScaffold<Content: View, Actions: View>: View {
    let title: String
    var detail = ""
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                    SKStatusStrip(title: title, detail: detail)
                    content
                }
                .padding(SK1.Metrics.paneMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            SKGroove()
            HStack(spacing: 8) { actions }
                .padding(.horizontal, SK1.Metrics.paneMargin)
                .padding(.vertical, 12)
        }
        .sk1Chassis()
    }
}

/// A caption over a field, as a settings group's caption sits over its tray.
struct CaptionedField<Field: View>: View {
    let caption: String
    var note: String?
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption(caption, tone: .soft)
            field
            if let note {
                Text(note).sk1Hint().fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Whether an item has a spot in the walk (issue #8): go by the trips, "Moves around" (always under Look for it at
/// the top of the list) or "Fixed spot" (always in the walk). Both item editors use it.
struct SpotField: View {
    @Binding var selection: WanderOverride?
    /// Whether the trips say it wanders.
    let tripsSayWanders: Bool
    @Environment(Profile.self) private var profile

    var body: some View {
        CaptionedField(caption: "Spot", note: note) {
            SKSegmented(selection: $selection, options: [
                SKSegmented<WanderOverride?>.Option(nil, "Learn it", help: "Go by where trips find it"),
                SKSegmented<WanderOverride?>.Option(.wanders, "Moves around", help: "Always under Look for it"),
                SKSegmented<WanderOverride?>.Option(.fixed, "Fixed spot", help: "Always in the walk"),
            ], height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selection) { _, spot in
                if spot != nil { profile.markTried(Milestones.Try.spot) }
            }
        }
    }

    private var note: String {
        switch selection {
        case .wanders: return "Always under Look for it at the top of the list, with where it's been seen."
        case .fixed: return "Always in the walk, even when trips find it in different places."
        case nil:
            return tripsSayWanders
                ? "Trips find it all over the store, so it's under Look for it until three trips agree."
                : "If trips keep finding it in different places, it moves to Look for it at the top of the list."
        }
    }
}
