import CoreData
import SwiftUI
import SK1Tokens
import SK1UI
import ShoppingCore
import ShoppingStore

/// A pharmacy locker pickup, typed in: the code from the pharmacy's text, who it's for and how many days the locker
/// holds it. It goes on the list at the pharmacy lockers, with the code in the note. Pasting the whole text in the
/// code field fills everything in.
struct LockerCodeSheet: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var context
    @Environment(Profile.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var name = ""
    @State private var days = 5

    private var service: ListService { ListService(context: context) }

    /// The pickup as typed: the whole text pasted in, or just the code.
    private var pickup: LockerPickup? {
        if let pasted = LockerPickup.parse(code) {
            return LockerPickup(code: pasted.code, name: pasted.name ?? cleanedName, days: pasted.days ?? days)
        }
        let typed = code.filter { $0.isLetter || $0.isNumber }.uppercased()
        guard typed.count >= 3 else { return nil }
        return LockerPickup(code: typed, name: cleanedName, days: days)
    }

    private var cleanedName: String? {
        let cleaned = ItemName.cleaned(name)
        return cleaned.isEmpty ? nil : cleaned
    }

    var body: some View {
        SheetScaffold(title: "Locker code", detail: pickup.map { "CODE \($0.code)" } ?? "PHARMACY PICKUP") {
            CaptionedField(caption: "Pickup code", note: "From the pharmacy's text. You can paste the whole text.") {
                SKTextField("Pickup code", text: $code, prompt: "AVQHTH")
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            CaptionedField(caption: "For", note: "Whose order it is, if you like.") {
                SKTextField("For", text: $name, prompt: profile.name.isEmpty ? "Name" : profile.name)
                    .textInputAutocapitalization(.words)
            }
            CaptionedField(caption: "Pick up within") {
                SKPicker(selection: $days, options: (1...14).map {
                    SKPicker<Int>.Option($0, $0 == 1 ? "1 day" : "\($0) days")
                })
            }
            Text("It goes on the list as Pharmacy locker pickup, at the pharmacy lockers, with the code, who it's for "
                 + "and the last day to pick it up. Check it off once you've got it.")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            Button("Cancel") { dismiss() }.buttonStyle(.sk1Key())
            Spacer()
            Button("Add", action: add)
                .buttonStyle(.sk1Key(.orange))
                .disabled(pickup == nil)
        }
    }

    private func add() {
        guard let pickup else { return }
        service.addLockerPickup(pickup, to: store, by: profile.shopper)
        do {
            try service.save()
        } catch {
            context.rollback()
            print("Buck Fifty: save failed: \(error)")
        }
        dismiss()
    }
}
