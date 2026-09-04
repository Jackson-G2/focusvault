import SwiftUI
import FocusVaultCore

struct FocusVaultDashboard: View {
    @EnvironmentObject private var model: FocusVaultAppModel
    @EnvironmentObject private var tracker: ProductivityTracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var intentionDraft = ""
    @State private var selectedDuration = 50
    @State private var hasAppeared = false

    private let sessionDurations = [25, 50, 90]

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                        .padding(.bottom, 24)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 20) {
                            focusColumn
                                .frame(maxWidth: .infinity)
                            utilityColumn
                                .frame(width: 286)
                        }

                        VStack(alignment: .leading, spacing: 20) {
                            focusColumn
                            utilityColumn
                        }
                    }

                    if let error = model.lastError {
                        errorBanner(error)
                            .padding(.top, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 28)
                .frame(maxWidth: 1020)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            model.refresh()
            tracker.start()
            intentionDraft = model.intention
            hasAppeared = true
        }
        .onChange(of: model.intention) { newValue in
            guard newValue != intentionDraft else { return }
            intentionDraft = newValue
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: model.lastError)
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            HStack(spacing: 10) {
                GlassIcon(systemName: "shield.lefthalf.filled", tint: Tideglass.signal, size: 32)
                Text("FocusVault")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Tideglass.ink)
            }

            Spacer()

            GlassPill(
                title: model.isBusy ? "Working" : (model.isSystemBlocked ? "Vaulted" : "Open"),
                systemImage: model.isSystemBlocked ? "lock.fill" : "lock.open",
                tint: model.isBusy ? Tideglass.signal : (model.isSystemBlocked ? Tideglass.seafoam : Tideglass.muted)
            )
        }
        .opacity(hasAppeared || reduceMotion ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : -6)
    }

    private var focusColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            intentionCard
            sessionCard
        }
    }

    private var utilityColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            protectionCard
            ProductivityCalendar(log: tracker.log)
        }
    }

    private var intentionCard: some View {
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
                }

                Text("A reason is enough.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
            }
            .padding(24)
        }
    }

    private var sessionCard: some View {
        GlassCard(cornerRadius: 26, tint: model.sessionPhase == .active ? Tideglass.signal : Tideglass.seafoam) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 9) {
                        FocusPulse(isActive: model.sessionPhase == .active, isComplete: model.sessionPhase == .completed)
                        Text(sessionHeading)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                    }
                    Spacer()
                    if model.sessionPhase == .active {
                        Text("\(Int(model.sessionDuration / 60)) min")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.muted)
                    }
                }

                sessionContent
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        switch model.sessionPhase {
        case .ready:
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 18) {
                    SessionDial(
                        progress: 0,
                        seconds: selectedDuration * 60,
                        state: .ready,
                        reduceMotion: reduceMotion
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("One quiet stretch")
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text(model.isSystemBlocked ? "The vault is already ready." : "Starting will engage the full vault.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(sessionDurations, id: \.self) { minutes in
                        durationButton(minutes)
                    }
                }

                Button("Start focus") {
                    model.startFocusSession(minutes: selectedDuration) { _ in }
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                .disabled(model.isBusy)
            }

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

                    Text("The vault stays closed until you choose otherwise.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("End session") {
                        model.endFocusSession()
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
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

                Button("Start another focus") {
                    model.startFocusSession(minutes: selectedDuration) { _ in }
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                .disabled(model.isBusy)
            }
        }
    }

    private func durationButton(_ minutes: Int) -> some View {
        Button {
            selectedDuration = minutes
        } label: {
            Text("\(minutes)m")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(selectedDuration == minutes ? Tideglass.canvas : Tideglass.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    Capsule()
                        .fill(selectedDuration == minutes ? Tideglass.signal : Tideglass.elevated.opacity(0.46))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            selectedDuration == minutes ? Tideglass.signal : Tideglass.line,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedDuration)
    }

    private var protectionCard: some View {
        GlassCard(cornerRadius: 24, tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.signal) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("PROTECTION")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(Tideglass.muted)
                    Spacer()
                    GlassPill(
                        title: model.isSystemBlocked ? "On" : "Off",
                        systemImage: model.isSystemBlocked ? "checkmark" : "minus",
                        tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.muted
                    )
                }

                HStack(spacing: 12) {
                    GlassIcon(
                        systemName: model.isSystemBlocked ? "lock.fill" : "lock.open",
                        tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.signal,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Full vault")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text(model.isSystemBlocked ? "YouTube is closed everywhere" : "YouTube is open")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.toggleFullVault()
                    } label: {
                        Image(systemName: model.isSystemBlocked ? "lock.open.fill" : "lock.fill")
                    }
                    .buttonStyle(GlassButtonStyle(tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.signal, isProminent: true))
                    .disabled(model.isBusy)
                    .help(model.isSystemBlocked ? "Open full vault" : "Engage full vault")
                    .accessibilityLabel(model.isSystemBlocked ? "Open full vault" : "Engage full vault")
                }

                Divider().overlay(Tideglass.line)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Channel vault")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text("Keep trusted channels only")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                    }
                    Spacer()
                    Button {
                        model.revealBrowserCompanion()
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                    .help("Open channel-vault setup")
                    .accessibilityLabel("Open channel-vault setup")
                }
            }
            .padding(20)
        }
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Tideglass.coral)
            Text(error)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Tideglass.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                model.clearError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
            .help("Dismiss error")
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Tideglass.coral.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Tideglass.coral.opacity(0.25), lineWidth: 1)
                }
        }
    }

    private var sessionHeading: String {
        switch model.sessionPhase {
        case .ready: return "Focus session"
        case .active: return "In focus"
        case .completed: return "Session complete"
        }
    }
}

private enum SessionDialState {
    case ready
    case active
}

private struct SessionDial: View {
    let progress: Double
    let seconds: Int
    let state: SessionDialState
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tideglass.line.opacity(0.8), lineWidth: 10)

            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(
                    Tideglass.signal,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress)

            VStack(spacing: 1) {
                Text(timeText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Tideglass.ink)
                Text(state == .active ? "remaining" : "minutes")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tideglass.muted)
            }
        }
        .frame(width: 138, height: 138)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state == .active ? "\(timeText) remaining" : "\(timeText) minute focus session")
    }

    private var timeText: String {
        let totalMinutes = max(0, seconds / 60)
        let remainingSeconds = max(0, seconds % 60)
        if state == .ready {
            return "\(totalMinutes)"
        }
        return String(format: "%02d:%02d", totalMinutes, remainingSeconds)
    }
}

private struct FocusPulse: View {
    let isActive: Bool
    let isComplete: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isComplete ? Tideglass.seafoam : (isActive ? Tideglass.signal : Tideglass.muted))
                .frame(width: 8, height: 8)
            if isActive && !reduceMotion {
                Circle()
                    .stroke(Tideglass.signal.opacity(0.55), lineWidth: 1)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 2.7 : 1)
                    .opacity(isPulsing ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: isPulsing)
            }
        }
        .frame(width: 12, height: 12)
        .onAppear {
            guard isActive && !reduceMotion else { return }
            isPulsing = true
        }
        .onChange(of: isActive) { active in
            guard active && !reduceMotion else {
                isPulsing = false
                return
            }
            isPulsing = true
        }
    }
}

private struct CompletionMark: View {
    let reduceMotion: Bool
    @State private var isVisible = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Tideglass.seafoam.opacity(0.16))
                .frame(width: 62, height: 62)
            Circle()
                .stroke(Tideglass.seafoam, lineWidth: 2)
                .frame(width: 48, height: 48)
                .scaleEffect(isVisible || reduceMotion ? 1 : 0.72)
                .opacity(isVisible || reduceMotion ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Tideglass.seafoam)
                .scaleEffect(isVisible || reduceMotion ? 1 : 0.7)
                .opacity(isVisible || reduceMotion ? 1 : 0)
        }
        .frame(width: 62, height: 62)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                isVisible = true
            }
        }
    }
}
