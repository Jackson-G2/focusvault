import SwiftUI
import VaultyCore

@MainActor
struct FocusVaultDashboard: View {
    @EnvironmentObject private var model: FocusVaultAppModel
    @EnvironmentObject private var tracker: ProductivityTracker
    @EnvironmentObject private var learningGuide: VideoResearchModel
    @EnvironmentObject private var toolsManager: LocalToolsManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var intentionDraft = ""
    @State private var taskEstimateText = "40"
    @State private var hasAppeared = false
    @State private var showingLearningGuide = false
    @State private var showingSleepCalculator = false
    @StateObject private var dashboardLayout: DashboardLayoutModel
    @State private var draggedWidget: DashboardWidgetKind?

    init() {
        _dashboardLayout = StateObject(wrappedValue: DashboardLayoutModel())
    }

    init(dashboardLayout: DashboardLayoutModel) {
        _dashboardLayout = StateObject(wrappedValue: dashboardLayout)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                        .padding(.bottom, 24)

                    DashboardWidgetCanvas(
                        model: dashboardLayout,
                        draggedWidget: $draggedWidget,
                        reduceMotion: reduceMotion
                    ) { kind in
                        dashboardWidget(kind)
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
        .sheet(isPresented: $showingLearningGuide) {
            VideoRecommendationsView()
                .environmentObject(learningGuide)
        }
        .sheet(isPresented: $showingSleepCalculator) {
            SleepCalculatorView()
        }
        .sheet(
            item: Binding(
                get: { model.unlockChallengeRequest },
                set: { request in
                    if request == nil, model.unlockChallengeRequest != nil {
                        model.cancelUnlockChallenge()
                    }
                }
            )
        ) { _ in
            ZStack {
                if let kind = model.selectedUnlockChallengeKind {
                    switch kind {
                    case .gridShot:
                        GridShotChallengeView(
                            onComplete: model.completeUnlockChallenge,
                            onFailure: model.failUnlockChallenge,
                            onCancel: model.cancelUnlockChallenge,
                            onChooseAnother: model.returnToUnlockTaskHub,
                            isUnlocking: model.isBusy,
                            unlockError: model.unlockSubmissionError
                        )
                    case .typingSprint:
                        TypingSprintChallengeView(
                            onComplete: model.completeUnlockChallenge,
                            onFailure: model.failUnlockChallenge,
                            onCancel: model.cancelUnlockChallenge,
                            onChooseAnother: model.returnToUnlockTaskHub,
                            isUnlocking: model.isBusy,
                            unlockError: model.unlockSubmissionError
                        )
                    case .signalShift:
                        SignalShiftChallengeView(
                            onComplete: model.completeUnlockChallenge,
                            onLockedOut: model.failUnlockChallenge,
                            onCancel: model.cancelUnlockChallenge,
                            onChooseAnother: model.returnToUnlockTaskHub,
                            isUnlocking: model.isBusy,
                            unlockError: model.unlockSubmissionError
                        )
                    }
                } else {
                    UnlockTaskHubView(
                        onSelect: model.chooseUnlockChallenge,
                        onCancel: model.cancelUnlockChallenge
                    )
                }
            }
            .frame(width: UnlockChallengeLayout.width, height: UnlockChallengeLayout.height)
            .clipped()
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            HStack(spacing: 10) {
                VaultyMascot(size: 32, isProtected: model.isAnyVaultBlocked)
                Text("Vaulty")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Tideglass.ink)
            }

            Spacer()

            if dashboardLayout.isEditing {
                Button("Reset") {
                    withAnimation { dashboardLayout.reset() }
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                .help("Restore the default widget positions and sizes")
                .accessibilityIdentifier("reset-dashboard-widgets")
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    dashboardLayout.isEditing.toggle()
                    if !dashboardLayout.isEditing { draggedWidget = nil }
                }
            } label: {
                Label(
                    dashboardLayout.isEditing ? "Done" : "Arrange",
                    systemImage: dashboardLayout.isEditing ? "checkmark" : "square.grid.2x2"
                )
            }
            .buttonStyle(GlassButtonStyle(
                tint: dashboardLayout.isEditing ? Tideglass.signal : Tideglass.muted,
                isProminent: dashboardLayout.isEditing
            ))
            .help(dashboardLayout.isEditing ? "Finish arranging and resizing widgets" : "Move and resize dashboard widgets")
            .accessibilityIdentifier("arrange-dashboard-widgets")

            GlassPill(
                title: model.isBusy ? "Working" : (model.isAnyVaultBlocked ? "Vaulted" : "Open"),
                lockState: model.isAnyVaultBlocked ? .locked : .open,
                tint: model.isBusy ? Tideglass.signal : (model.isAnyVaultBlocked ? Tideglass.seafoam : Tideglass.muted)
            )
        }
        .opacity(hasAppeared || reduceMotion ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : -6)
    }

    @ViewBuilder
    private func dashboardWidget(_ kind: DashboardWidgetKind) -> some View {
        switch kind {
        case .intention:
            intentionCard
        case .taskClock:
            taskClockCard
        case .youtubeProtection:
            protectionCard
        case .shortFormProtection:
            shortFormProtectionCard
        case .localTools:
            LocalToolsWidget()
        case .sleepCalculator:
            sleepCalculatorCard
        case .learningGuide:
            learningGuideCard
        case .rhythm:
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
                        .accessibilityIdentifier("intention-field")
                }

                Text("A reason is enough.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var taskClockCard: some View {
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

    private var sleepCalculatorCard: some View {
        GlassCard(cornerRadius: 20, tint: Tideglass.seafoam) {
            HStack(spacing: 12) {
                GlassIcon(systemName: "bed.double.fill", tint: Tideglass.seafoam, size: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sleep calculator")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.ink)
                    Text("Plan bedtime from sleep cycles")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Button {
                    showingSleepCalculator = true
                } label: {
                    Text("Open")
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.seafoam, isProminent: true))
                .help("Open sleep calculator")
                .accessibilityLabel("Open sleep calculator")
                .accessibilityIdentifier("open-sleep-calculator")
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var learningGuideCard: some View {
        GlassCard(cornerRadius: 20, tint: Tideglass.signal) {
            HStack(spacing: 12) {
                GlassIcon(systemName: "sparkles", tint: Tideglass.signal, size: 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text("Learn next")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        if learningGuide.isResearching {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Tideglass.signal)
                        }
                    }
                    Text(learningGuideSubtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                if !learningGuide.isResearching {
                    Button {
                        if learningGuide.result != nil {
                            showingLearningGuide = true
                        } else {
                            learningGuide.research()
                        }
                    } label: {
                        Text(learningGuideActionTitle)
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                    .help(learningGuideActionTitle)
                    .accessibilityLabel(learningGuideActionTitle)
                    .accessibilityIdentifier("learning-guide-action")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var learningGuideSubtitle: String {
        if learningGuide.isResearching {
            return learningGuide.statusText
        }
        if let error = learningGuide.researchError {
            return error
        }
        if let result = learningGuide.result, !result.recommendations.isEmpty {
            return "\(result.recommendations.count) transcript-backed lesson\(result.recommendations.count == 1 ? "" : "s") ready"
        }
        if let diagnostic = learningGuide.result?.diagnostics.first {
            return diagnostic
        }
        return "Local agent history → useful video lessons"
    }

    private var learningGuideActionTitle: String {
        if let result = learningGuide.result {
            return result.recommendations.isEmpty ? "View" : "Open"
        }
        return learningGuide.researchError == nil ? "Research" : "Retry"
    }

    private var protectionCard: some View {
        GlassCard(cornerRadius: 24, tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.signal) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("YOUTUBE PROTECTION")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(Tideglass.muted)
                    Spacer()
                    GlassPill(
                        title: model.isSystemBlocked ? "Locked" : model.youtubeUnlockTimeText,
                        lockState: model.isSystemBlocked ? .locked : .open,
                        tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.signal
                    )
                }

                HStack(spacing: 12) {
                    GlassIcon(
                        lockState: model.isSystemBlocked ? .locked : .open,
                        tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.signal,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YouTube blocker")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text(model.isSystemBlocked
                            ? "Task + administrator approval"
                            : "Open now · auto-locks at 45 minutes")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.toggleFullVault()
                    } label: {
                        HStack(spacing: 6) {
                            VaultLockGlyph(state: model.isSystemBlocked ? .locked : .open, size: 14)
                            Text(model.isSystemBlocked ? "Unlock" : "Lock now")
                        }
                    }
                    .buttonStyle(GlassButtonStyle(tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.signal, isProminent: true))
                    .disabled(model.isBusy)
                    .help(model.isSystemBlocked ? "Choose a task, win, then approve the 45-minute unlock" : "Lock YouTube without a password")
                    .accessibilityLabel(model.isSystemBlocked ? "Unlock YouTube for 45 minutes" : "Lock YouTube now without a password")
                    .accessibilityIdentifier("toggle-youtube-vault")
                }

                Text(model.isGuardInstalled
                    ? "Lock anytime with no password. Every unlock lasts 45 minutes."
                    : "One administrator approval installs the guard; after that, only unlocking asks for a password.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Tideglass.line)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Channel vault")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text("Keep trusted YouTube channels only")
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
                    .accessibilityIdentifier("open-channel-vault-setup")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var shortFormProtectionCard: some View {
        GlassCard(cornerRadius: 24, tint: model.isShortFormBlocked ? Tideglass.seafoam : Tideglass.signal) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("SHORT-FORM PROTECTION")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(Tideglass.muted)
                    Spacer()
                    GlassPill(
                        title: model.isShortFormBlocked ? "On" : "Off",
                        systemImage: model.isShortFormBlocked ? "checkmark" : "minus",
                        tint: model.isShortFormBlocked ? Tideglass.seafoam : Tideglass.muted
                    )
                }

                HStack(spacing: 12) {
                    GlassIcon(
                        systemName: model.isShortFormBlocked ? "hourglass" : "hourglass.bottomhalf.filled",
                        tint: model.isShortFormBlocked ? Tideglass.seafoam : Tideglass.signal,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Short-form blocker")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text(model.isShortFormBlocked
                            ? "TikTok, Reels, and Shorts are closed"
                            : "TikTok, Reels, and Shorts are open")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.toggleShortFormVault()
                    } label: {
                        VaultLockGlyph(state: model.isShortFormBlocked ? .locked : .open, size: 15)
                    }
                    .buttonStyle(GlassButtonStyle(tint: model.isShortFormBlocked ? Tideglass.seafoam : Tideglass.signal, isProminent: true))
                    .disabled(model.isBusy || model.youtubeUnlockRemainingSeconds > 0)
                    .help(model.youtubeUnlockRemainingSeconds > 0
                        ? "Lock YouTube before changing system-wide short-form protection"
                        : (model.isShortFormBlocked ? "Open short-form blocker" : "Engage short-form blocker"))
                    .accessibilityLabel(model.isShortFormBlocked ? "Open short-form blocker" : "Engage short-form blocker")
                    .accessibilityIdentifier("toggle-short-form-vault")
                }

                Text("TikTok · Instagram Reels · YouTube Shorts · Facebook Reels")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .accessibilityIdentifier("dismiss-error")
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

private enum SessionDialState {
    case ready
    case active
    case paused
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
                Text(stateLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tideglass.muted)
            }
        }
        .frame(width: 138, height: 138)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var timeText: String {
        let totalMinutes = max(0, seconds / 60)
        let remainingSeconds = max(0, seconds % 60)
        if state == .ready {
            return "\(totalMinutes)"
        }
        return String(format: "%02d:%02d", totalMinutes, remainingSeconds)
    }

    private var stateLabel: String {
        switch state {
        case .ready: return "minutes"
        case .active: return "remaining"
        case .paused: return "paused"
        }
    }

    private var accessibilityText: String {
        switch state {
        case .ready:
            return "\(timeText) minute task estimate"
        case .active:
            return "\(timeText) remaining"
        case .paused:
            return "\(timeText) paused"
        }
    }
}

private struct FocusPulse: View {
    let isActive: Bool
    let isPaused: Bool
    let isComplete: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isComplete ? Tideglass.seafoam : ((isActive || isPaused) ? Tideglass.signal : Tideglass.muted))
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
