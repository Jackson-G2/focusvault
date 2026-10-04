import SwiftUI
import VaultyCore

@MainActor
struct IntentionWidget: View {
    @EnvironmentObject private var model: FocusVaultAppModel
    @State private var intentionDraft = ""

    var body: some View {
        GlassCard(cornerRadius: 26, tint: Tideglass.seafoam) {
            VStack(alignment: .leading, spacing: 18) {
                Text("PROTECTING")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Tideglass.seafoam)

                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Tideglass.signal)
                        .padding(.top, 5)

                    TextField("What are you protecting?", text: $intentionDraft)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.ink)
                        .textFieldStyle(.plain)
                        .lineLimit(2)
                        .onChange(of: intentionDraft) { newValue in
                            model.saveIntention(newValue)
                        }
                        .onSubmit {
                            model.saveIntention(intentionDraft)
                        }
                        .accessibilityIdentifier("intention-field")
                }

                Text("A reason is enough.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { intentionDraft = model.intention }
        .onChange(of: model.intention) { newValue in
            if newValue != intentionDraft { intentionDraft = newValue }
        }
    }
}
