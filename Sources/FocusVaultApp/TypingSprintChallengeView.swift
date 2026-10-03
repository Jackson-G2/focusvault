import SwiftUI
import VaultyCore

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
        case .failed: return "Choose an unlock task again to retry."
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
        // The display shows tenths; absolute timestamps keep input/final timing
        // exact without waking the entire screen twice per displayed value.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in tick() }
        timer?.tolerance = 0.02
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
