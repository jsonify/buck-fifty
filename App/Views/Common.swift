import SwiftUI
import SK1Tokens
import SK1UI

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
