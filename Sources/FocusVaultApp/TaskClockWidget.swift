import SwiftUI
import VaultyCore

@MainActor
struct TaskClockWidget: View {
    @EnvironmentObject private var model: FocusVaultAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taskEstimateText = "40"

    var body: some View {
        GlassCard(
            cornerRadius: 26,
            tint: (model.sessionPhase == .active || model.sessionPhase == .paused)
                ? Tideglass.signal
                : Tideglass.seafoam
        ) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 9) {
                        FocusPulse(
                            isActive: model.sessionPhase == .active,
                            isPaused: model.sessionPhase == .paused,
                            isComplete: model.sessionPhase == .completed
                        )
                        Text(sessionHeading)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                    }
                    Spacer()
                    if model.sessionPhase == .active || model.sessionPhase == .paused {
                        Text("\(Int(model.sessionDuration / 60)) min")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.muted)
                    }
                }

                taskClockContent
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var taskClockContent: some View {
        switch model.sessionPhase {
        case .ready:
            taskClockReadyContent

        case .active:
            HStack(alignment: .center, spacing: 20) {
                SessionDial(
                    progress: model.sessionProgress,
                    seconds: model.remainingSessionSeconds,
                    state: .active,
                    reduceMotion: reduceMotion
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text(model.intention.isEmpty ? "Stay with it." : model.intention)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.ink)
                        .lineLimit(3)

                    Text("The YouTube blocker stays closed until you choose otherwise.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            model.pauseFocusSession()
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.signal))
                        .accessibilityIdentifier("pause-task-clock")

                        Button("End clock") {
                            model.endFocusSession()
                        }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                        .accessibilityIdentifier("end-task-clock")
                    }
                }
            }

        case .paused:
            HStack(alignment: .center, spacing: 20) {
                SessionDial(
                    progress: model.sessionProgress,
                    seconds: model.remainingSessionSeconds,
                    state: .paused,
                    reduceMotion: reduceMotion
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text(model.intention.isEmpty ? "Your place is held." : model.intention)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.ink)
                        .lineLimit(3)

                    Text("The clock is paused. Nothing is being spent.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            model.resumeFocusSession()
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                        }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                        .accessibilityIdentifier("resume-task-clock")

                        Button("End clock") {
                            model.endFocusSession()
                        }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                        .accessibilityIdentifier("end-paused-task-clock")
                    }
                }
            }

        case .completed:
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 14) {
                    CompletionMark(reduceMotion: reduceMotion)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You kept the room.")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text(model.intention.isEmpty ? "That time was yours." : model.intention)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                            .lineLimit(2)
                    }
                }

                Button {
                    startTaskClock()
                } label: {
                    startTaskButtonLabel(defaultTitle: "Start another task")
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                .disabled(model.isBusy || taskEstimateMinutes == nil)
                .accessibilityIdentifier("start-another-task-clock")
            }
        }
    }

    private var taskClockReadyContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                SessionDial(
                    progress: 0,
                    seconds: estimateSeconds,
                    state: .ready,
                    reduceMotion: reduceMotion
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Set the time before you start.")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.ink)
                    Text(model.isSystemBlocked ? "The YouTube blocker is already ready." : "Starting will block YouTube.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            estimateField

            Button {
                startTaskClock()
            } label: {
                startTaskButtonLabel(defaultTitle: "Start task")
            }
            .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
            .disabled(model.isBusy || taskEstimateMinutes == nil)
            .accessibilityIdentifier("start-task-clock")
        }
    }

    private var estimateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Estimate")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tideglass.muted)
                Spacer()
                ZStack(alignment: .trailing) {
                    TextField("40", text: $taskEstimateText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 24)
                        .padding(.leading, 8)
                        .padding(.trailing, 24)
                        .onChange(of: taskEstimateText) { newValue in
                            let digits = String(newValue.filter { $0.isNumber }.prefix(3))
                            if digits != newValue {
                                taskEstimateText = digits
                            }
                        }
                        .onSubmit {
                            taskEstimateText = String(taskEstimateMinutes ?? 40)
                        }

                    Text("min")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.muted)
                        .padding(.trailing, 10)
                        .allowsHitTesting(false)
                }
                .frame(width: 82, height: 40)
                .background {
                    Capsule()
                        .fill(Tideglass.elevated.opacity(0.58))
                        .overlay {
                            Capsule().strokeBorder(
                                taskEstimateMinutes == nil ? Tideglass.coral.opacity(0.60) : Tideglass.line,
                                lineWidth: 1
                            )
                        }
                }
                .contentShape(Capsule())
                .help("Edit task estimate in minutes")
                .accessibilityLabel("Task estimate in minutes")
                .accessibilityIdentifier("task-estimate-field")
            }

            if taskEstimateMinutes == nil {
                Text("Enter 1–240 minutes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Tideglass.coral)
            }
        }
    }

    private var taskEstimateMinutes: Int? {
        guard let minutes = Int(taskEstimateText), (1...240).contains(minutes) else {
            return nil
        }
        return minutes
    }

    private var estimateSeconds: Int {
        (taskEstimateMinutes ?? 0) * 60
    }

    private func startTaskClock() {
        guard let minutes = taskEstimateMinutes else { return }
        model.startFocusSession(minutes: minutes) { _ in }
    }

    private func startTaskButtonLabel(defaultTitle: String) -> some View {
        HStack(spacing: 8) {
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.isBusy ? "Starting…" : defaultTitle)
        }
        .frame(minWidth: 108)
    }

    private var sessionHeading: String {
        switch model.sessionPhase {
        case .ready: return "Task clock"
        case .active: return "In focus"
        case .paused: return "Clock paused"
        case .completed: return "Time kept"
        }
    }
}
