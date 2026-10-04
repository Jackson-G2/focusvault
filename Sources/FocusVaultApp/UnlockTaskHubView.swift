import SwiftUI
import VaultyCore

struct UnlockTaskHubView: View {
    let onSelect: (UnlockChallengeKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 24) {
                VStack(spacing: 7) {
                    GlassIcon(systemName: "square.grid.2x2.fill", tint: Tideglass.signal, size: 46)
                    Text("Choose your unlock task")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Tideglass.ink)
                    Text("Choose a task. Administrator approval comes after you win.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                    spacing: 14
                ) {
                    taskCard(
                        kind: .gridShot,
                        icon: "scope",
                        tint: Tideglass.signal,
                        summary: "Hit three moving targets. Ten seconds, +1 hit, −1 miss."
                    )
                    taskCard(
                        kind: .typingSprint,
                        icon: "keyboard.fill",
                        tint: Tideglass.seafoam,
                        summary: "Type one short focus phrase exactly. No speed or time cutoff."
                    )
                    taskCard(
                        kind: .signalShift,
                        icon: "brain.head.profile",
                        tint: Tideglass.signal,
                        summary: "Optional spatial-memory path. It is never required for access."
                    )
                }

                Button("Cancel") { onCancel() }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                    .accessibilityIdentifier("cancel-unlock-task-hub")
            }
            .padding(30)
            .frame(maxWidth: 650)
        }
        .preferredColorScheme(.dark)
        .frame(width: UnlockChallengeLayout.width, height: UnlockChallengeLayout.height)
    }

    private func taskIdentifier(for kind: UnlockChallengeKind) -> String {
        switch kind {
        case .gridShot: return "choose-unlock-gridShot"
        case .typingSprint: return "choose-unlock-typingSprint"
        case .signalShift: return "choose-unlock-signalShift"
        }
    }

    private func taskCard(
        kind: UnlockChallengeKind,
        icon: String,
        tint: Color,
        summary: String
    ) -> some View {
        GlassCard(cornerRadius: 22, tint: tint) {
            VStack(alignment: .leading, spacing: 13) {
                GlassIcon(systemName: icon, tint: tint, size: 42)
                Text(kind.displayName)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Tideglass.ink)
                Text(summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Choose \(kind.displayName)") {
                    onSelect(kind)
                }
                .buttonStyle(GlassButtonStyle(tint: tint, isProminent: true))
                .accessibilityIdentifier(taskIdentifier(for: kind))
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }
}
