import SwiftUI
import VaultyCore

enum UnlockChallengeLayout {
    static let width: CGFloat = 760
    static let height: CGFloat = 760
}

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
                        summary: "Type one short focus phrase exactly within 24 seconds."
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

enum UnlockGamePhase: Equatable {
    case ready
    case running
    case success
    case failed
}

struct GridShotChallengeView: View {
    let onComplete: () -> Void
    let onFailure: () -> Void
    let onCancel: () -> Void
    let onChooseAnother: () -> Void
    let isUnlocking: Bool
    let unlockError: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var run = GridShotRun(seed: GridShotChallengeView.randomSeed())
    @State private var phase: UnlockGamePhase
    @State private var remaining = Double(GridShotRun.durationSeconds)
    @State private var deadline: Date?
    @State private var timer: Timer?
    @State private var lastMissPoint: GridShotPoint?
    @State private var missMarkerID = UUID()
    @State private var pressHandled = false

    init(
        onComplete: @escaping () -> Void,
        onFailure: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onChooseAnother: @escaping () -> Void,
        isUnlocking: Bool,
        unlockError: String?,
        initialPhase: UnlockGamePhase = .ready
    ) {
        self.onComplete = onComplete
        self.onFailure = onFailure
        self.onCancel = onCancel
        self.onChooseAnother = onChooseAnother
        self.isUnlocking = isUnlocking
        self.unlockError = unlockError
        _phase = State(initialValue: initialPhase)
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                header
                rules
                aimArena
                status
                controls
            }
            .padding(28)
            .frame(maxWidth: 650)
        }
        .preferredColorScheme(.dark)
        .frame(width: UnlockChallengeLayout.width, height: UnlockChallengeLayout.height)
        .onDisappear { timer?.invalidate() }
    }

    private var header: some View {
        HStack(spacing: 13) {
            GlassIcon(systemName: "scope", tint: Tideglass.signal, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text("Grid Shot")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Tideglass.ink)
                Text("Aim training · approve unlock after you win")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f", remaining))
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(remaining <= 3 && phase == .running ? Tideglass.coral : Tideglass.signal)
                Text("seconds")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Tideglass.muted)
            }
        }
    }

    private var rules: some View {
        GlassCard(cornerRadius: 18, tint: Tideglass.signal) {
            HStack(spacing: 14) {
                stat(title: "Targets", value: "3")
                Divider().overlay(Tideglass.line).frame(height: 34)
                stat(title: "Goal", value: "30")
                Divider().overlay(Tideglass.line).frame(height: 34)
                stat(title: "Hit", value: "+1")
                Divider().overlay(Tideglass.line).frame(height: 34)
                stat(title: "Miss", value: "−1")
            }
            .padding(14)
        }
    }

    private func stat(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Tideglass.ink)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Tideglass.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var aimArena: some View {
        GeometryReader { proxy in
            let scaleX = proxy.size.width / GridShotRun.arenaWidth
            let scaleY = proxy.size.height / GridShotRun.arenaHeight
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Tideglass.surface.opacity(0.54))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Tideglass.line, lineWidth: 1)
                    }

                ForEach(run.targets) { target in
                    Circle()
                        .fill(targetColor(target.id))
                        .overlay {
                            Circle().strokeBorder(Tideglass.ink.opacity(0.28), lineWidth: 2)
                        }
                        .frame(
                            width: GridShotRun.targetRadius * 2 * scaleX,
                            height: GridShotRun.targetRadius * 2 * scaleY
                        )
                        .position(
                            x: target.point.x * scaleX,
                            y: target.point.y * scaleY
                        )
                        .shadow(color: targetColor(target.id).opacity(0.5), radius: 10)
                        .allowsHitTesting(false)
                }

                if let miss = lastMissPoint {
                    Text("Missed!")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Tideglass.coral)
                        .position(
                            x: min(max(miss.x * scaleX, 42), max(42, proxy.size.width - 42)),
                            y: min(max(miss.y * scaleY, 20), max(20, proxy.size.height - 20))
                        )
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Aim training arena")
            .accessibilityValue("Three targets, score \(run.score) of \(GridShotRun.targetScore)")
            .accessibilityIdentifier("grid-shot-arena")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { event in
                        guard !pressHandled else { return }
                        pressHandled = true
                        tap(at: GridShotPoint(
                            x: Double(event.startLocation.x / scaleX),
                            y: Double(event.startLocation.y / scaleY)
                        ))
                    }
                    .onEnded { _ in
                        pressHandled = false
                    }
            )
        }
        .aspectRatio(
            CGFloat(GridShotRun.arenaWidth / GridShotRun.arenaHeight),
            contentMode: .fit
        )
        .frame(maxWidth: 650)
    }

    private func targetColor(_ targetID: Int) -> Color {
        switch targetID % GridShotRun.targetCount {
        case 0: return Tideglass.signal
        case 1: return Tideglass.seafoam
        default: return Tideglass.coral
        }
    }

    private var status: some View {
        HStack {
            Text("Score")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tideglass.muted)
            Text("\(run.score)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(run.score >= GridShotRun.targetScore ? Tideglass.seafoam : Tideglass.ink)
            Spacer()
            Text(statusText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    unlockError != nil
                        ? Tideglass.coral
                        : (phase == .success ? Tideglass.seafoam : (phase == .failed ? Tideglass.coral : Tideglass.muted))
                )
        }
        .frame(minHeight: 38)
    }

    private var statusText: String {
        switch phase {
        case .ready: return "Click the circles as they relocate."
        case .running: return "Hit circles. Empty space costs −1."
        case .success:
            return unlockError ?? "Target cleared. Confirm to unlock YouTube."
        case .failed: return "Password required to retry."
        }
    }

    private var controls: some View {
        ZStack {
            HStack(spacing: 8) {
                Button(unlockError == nil ? "Cancel" : "Close") {
                    timer?.invalidate()
                    onCancel()
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))

                if phase == .ready {
                    Spacer()
                    Button {
                        onChooseAnother()
                    } label: {
                        Label("Tasks", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                    .accessibilityIdentifier("choose-another-grid-shot")
                } else {
                    Spacer()
                }
            }

            if phase == .ready {
                Button("Start 10 seconds") { start() }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                    .accessibilityIdentifier("start-grid-shot")
            } else if phase == .success {
                Button(unlockError == nil ? (isUnlocking ? "Unlocking…" : "Unlock YouTube") : "Close and retry") {
                    unlockError == nil ? onComplete() : onCancel()
                }
                .buttonStyle(GlassButtonStyle(
                    tint: unlockError == nil ? Tideglass.seafoam : Tideglass.coral,
                    isProminent: true
                ))
                .disabled(isUnlocking)
                .accessibilityIdentifier("confirm-grid-shot-unlock")
            }
        }
        .frame(minHeight: 44)
    }

    private func start() {
        run = GridShotRun(seed: Self.randomSeed())
        pressHandled = false
        remaining = Double(GridShotRun.durationSeconds)
        deadline = Date().addingTimeInterval(TimeInterval(GridShotRun.durationSeconds))
        phase = .running
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            tick()
        }
    }

    private func tap(at point: GridShotPoint) {
        guard phase == .running else { return }
        let outcome = run.tap(at: point)
        if case .miss = outcome {
            lastMissPoint = point
            let marker = UUID()
            missMarkerID = marker
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if missMarkerID == marker { lastMissPoint = nil }
            }
        }
        if run.hasReachedTarget {
            finish(success: true)
        }
    }

    private func tick() {
        guard phase == .running, let deadline else { return }
        remaining = max(0, deadline.timeIntervalSinceNow)
        if remaining <= 0 {
            finish(success: run.hasReachedTarget)
        }
    }

    private func finish(success: Bool) {
        timer?.invalidate()
        timer = nil
        remaining = max(0, remaining)
        phase = success ? .success : .failed
        if !success {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                onFailure()
            }
        }
    }

    private static func randomSeed() -> UInt64 {
        var generator = SystemRandomNumberGenerator()
        return UInt64.random(in: UInt64.min...UInt64.max, using: &generator)
    }
}

struct TypingSprintChallengeView: View {
    let onComplete: () -> Void
    let onFailure: () -> Void
    let onCancel: () -> Void
    let onChooseAnother: () -> Void
    let isUnlocking: Bool
    let unlockError: String?

    @State private var prompt = TypingSprint.prompt(seed: TypingSprintChallengeView.randomSeed())
    @State private var typed = ""
    @State private var phase: UnlockGamePhase
    @State private var elapsed = 0.0
    @State private var startedAt: Date?
    @State private var timer: Timer?
    @FocusState private var isInputFocused: Bool

    init(
        onComplete: @escaping () -> Void,
        onFailure: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onChooseAnother: @escaping () -> Void,
        isUnlocking: Bool,
        unlockError: String?,
        initialPhase: UnlockGamePhase = .ready
    ) {
        self.onComplete = onComplete
        self.onFailure = onFailure
        self.onCancel = onCancel
        self.onChooseAnother = onChooseAnother
        self.isUnlocking = isUnlocking
        self.unlockError = unlockError
        _phase = State(initialValue: initialPhase)
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 20) {
                header
                typingSurface
                metrics
                controls
            }
            .padding(30)
            .frame(maxWidth: 700)
        }
        .preferredColorScheme(.dark)
        .frame(width: UnlockChallengeLayout.width, height: UnlockChallengeLayout.height)
        .onDisappear { timer?.invalidate() }
        .onAppear {
            DispatchQueue.main.async { isInputFocused = true }
        }
        .onChange(of: typed) { _ in checkTypedText() }
    }

    private var header: some View {
        HStack(spacing: 13) {
            GlassIcon(systemName: "keyboard.fill", tint: Tideglass.seafoam, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text("Typing Sprint")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Tideglass.ink)
                Text("Monkeytype style · exact text wins")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f", elapsed))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Tideglass.seafoam)
                Text("seconds")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Tideglass.muted)
            }
        }
    }

    private var typingSurface: some View {
        GlassCard(cornerRadius: 22, tint: Tideglass.seafoam) {
            ZStack(alignment: .topLeading) {
                renderedPrompt
                    .font(.system(size: 25, weight: .medium, design: .monospaced))
                    .lineSpacing(12)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                TextField("", text: $typed)
                    .textFieldStyle(.plain)
                    .frame(width: 2, height: 2)
                    .opacity(0.01)
                    .focused($isInputFocused)
                    .disabled(phase == .success || phase == .failed)
                    .accessibilityLabel("Type the displayed words")
                    .accessibilityIdentifier("typing-sprint-input")
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 330, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { isInputFocused = true }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Typing words: \(prompt)")
        }
    }

    private var renderedPrompt: Text {
        let targetCharacters = Array(prompt)
        let typedCharacters = Array(typed)
        var output = Text("")

        for (index, character) in targetCharacters.enumerated() {
            var segment = Text(String(character))
            if index < typedCharacters.count {
                segment = segment.foregroundColor(
                    typedCharacters[index] == character ? Tideglass.seafoam : Tideglass.coral
                )
            } else {
                segment = segment.foregroundColor(Tideglass.muted.opacity(0.72))
            }
            if index == typedCharacters.count, phase != .success {
                segment = segment.underline(true, color: Tideglass.signal)
            }
            output = output + segment
        }
        return output
    }

    private var metrics: some View {
        let result = currentResult
        return HStack(spacing: 18) {
            metric("Accuracy", "\(Int((result.accuracy * 100).rounded()))%")
            metric("Speed", "\(Int(result.wordsPerMinute.rounded())) WPM")
            metric("Progress", "\(typed.count)/\(prompt.count)")
            Spacer()
            Text(statusText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    unlockError != nil
                        ? Tideglass.coral
                        : (phase == .success ? Tideglass.seafoam : (phase == .failed ? Tideglass.coral : Tideglass.muted))
                )
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Tideglass.ink)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Tideglass.muted)
        }
    }

    private var statusText: String {
        switch phase {
        case .ready: return "Start typing · no speed cutoff"
        case .running: return "Green is correct. Fix red characters."
        case .success:
            return unlockError ?? "Phrase cleared. Confirm to unlock YouTube."
        case .failed: return "Password required to retry."
        }
    }

    private var controls: some View {
        ZStack {
            HStack(spacing: 8) {
                Button(unlockError == nil ? "Cancel" : "Close") {
                    timer?.invalidate()
                    onCancel()
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))

                if phase == .ready {
                    Spacer()
                    Button {
                        onChooseAnother()
                    } label: {
                        Label("Tasks", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                    .accessibilityIdentifier("choose-another-typing-sprint")
                } else {
                    Spacer()
                }
            }

            if phase == .ready {
                Button("Start typing") { isInputFocused = true }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.seafoam, isProminent: true))
                    .accessibilityIdentifier("start-typing-sprint")
            } else if phase == .success {
                Button(unlockError == nil ? (isUnlocking ? "Unlocking…" : "Unlock YouTube") : "Close and retry") {
                    unlockError == nil ? onComplete() : onCancel()
                }
                .buttonStyle(GlassButtonStyle(
                    tint: unlockError == nil ? Tideglass.seafoam : Tideglass.coral,
                    isProminent: true
                ))
                .disabled(isUnlocking)
                .accessibilityIdentifier("confirm-typing-sprint-unlock")
            }
        }
        .frame(minHeight: 44)
    }

    private var currentResult: TypingSprintResult {
        TypingSprint.evaluate(
            typed: typed,
            target: prompt,
            elapsedSeconds: elapsedSeconds
        )
    }

    private var elapsedSeconds: TimeInterval {
        elapsed
    }

    private func beginTimingIfNeeded() {
        guard phase == .ready else { return }
        phase = .running
        let now = Date()
        startedAt = now
        elapsed = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in tick() }
    }

    private func checkTypedText() {
        guard phase == .ready || phase == .running else { return }
        if typed.count > prompt.count {
            typed = String(typed.prefix(prompt.count))
            return
        }
        if phase == .ready, !typed.isEmpty {
            beginTimingIfNeeded()
        }
        if typed == prompt {
            finish(success: true)
        }
    }

    private func tick() {
        guard phase == .running, let startedAt else { return }
        elapsed = max(0, Date().timeIntervalSince(startedAt))
    }

    private func finish(success: Bool) {
        if let startedAt {
            elapsed = max(0, Date().timeIntervalSince(startedAt))
        }
        timer?.invalidate()
        timer = nil
        isInputFocused = false
        phase = success ? .success : .failed
        if !success { onFailure() }
    }

    private static func randomSeed() -> UInt64 {
        var generator = SystemRandomNumberGenerator()
        return UInt64.random(in: UInt64.min...UInt64.max, using: &generator)
    }
}
