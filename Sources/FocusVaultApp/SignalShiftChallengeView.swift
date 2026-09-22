import SwiftUI
import VaultyCore

struct SignalShiftChallengeView: View {
    let onComplete: () -> Void
    let onLockedOut: () -> Void
    let onCancel: () -> Void
    let onChooseAnother: () -> Void
    let isUnlocking: Bool
    let unlockError: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var run: SignalShiftRun
    @State private var phase: Phase
    @State private var highlightedPoint: SignalGridPoint?
    @State private var enteredPoints: [SignalGridPoint] = []
    @State private var statusText = "Room one is a practice round with no life penalty."
    @State private var previewTask: Task<Void, Never>?

    enum Phase: Equatable {
        case ready
        case preview
        case input
        case feedback(correct: Bool)
        case completed
        case lockedOut
    }

    init(
        onComplete: @escaping () -> Void,
        onLockedOut: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onChooseAnother: @escaping () -> Void,
        isUnlocking: Bool,
        unlockError: String?,
        initialPhase: Phase = .ready,
        seed: UInt64? = nil
    ) {
        self.onComplete = onComplete
        self.onLockedOut = onLockedOut
        self.onCancel = onCancel
        self.onChooseAnother = onChooseAnother
        self.isUnlocking = isUnlocking
        self.unlockError = unlockError
        _run = State(initialValue: SignalShiftRun(seed: seed ?? Self.randomSeed()))
        _phase = State(initialValue: initialPhase)
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 22) {
                header
                ruleCard
                signalGrid
                progressSection
                controls
            }
            .padding(30)
            .frame(maxWidth: 650)
        }
        .preferredColorScheme(.dark)
        .frame(width: UnlockChallengeLayout.width, height: UnlockChallengeLayout.height)
        .onAppear {
            if phase == .ready { beginPreview() }
        }
        .onDisappear {
            previewTask?.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            GlassIcon(systemName: "brain.head.profile", tint: Tideglass.signal, size: 42)

            VStack(alignment: .leading, spacing: 5) {
                Text("Signal Shift")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Tideglass.ink)
                Text("Complete three rooms · approve unlock after you win")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: index < run.livesRemaining ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(index < run.livesRemaining ? Tideglass.coral : Tideglass.muted.opacity(0.45))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(run.livesRemaining) lives remaining")
        }
    }

    private var ruleCard: some View {
        GlassCard(cornerRadius: 20, tint: Tideglass.signal) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("ROOM \(run.level) OF 3")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(Tideglass.signal)
                    Spacer()
                    Text("\(run.puzzle.sequence.count) signals")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.muted)
                }

                Text(run.puzzle.instruction)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tideglass.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(run.level == 1
                    ? "Practice: watch three connected cells, then tap the same path. A mistake costs no life."
                    : "Watch the connected orange path. Replay is available before you answer.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
    }

    private var signalGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: SignalShiftPuzzle.gridSize)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<(SignalShiftPuzzle.gridSize * SignalShiftPuzzle.gridSize), id: \.self) { flatIndex in
                let point = SignalGridPoint(
                    row: flatIndex / SignalShiftPuzzle.gridSize,
                    column: flatIndex % SignalShiftPuzzle.gridSize
                )
                signalCell(point: point, flatIndex: flatIndex)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Tideglass.elevated.opacity(0.46))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Tideglass.line, lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Four by four Signal Shift grid")
    }

    private func signalCell(point: SignalGridPoint, flatIndex: Int) -> some View {
        let entryIndex = enteredPoints.firstIndex(of: point)
        let isHighlighted = highlightedPoint == point
        let isEntered = entryIndex != nil

        return Button {
            choose(point)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(cellFill(isHighlighted: isHighlighted, isEntered: isEntered))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(
                                isHighlighted ? Tideglass.signal : Tideglass.line,
                                lineWidth: isHighlighted ? 2 : 1
                            )
                    }

                if let entryIndex {
                    Text("\(entryIndex + 1)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Tideglass.ink)
                        .transition(.scale.combined(with: .opacity))
                } else if isHighlighted {
                    Circle()
                        .fill(Tideglass.ink)
                        .frame(width: 15, height: 15)
                        .shadow(color: Tideglass.signal.opacity(0.7), radius: 8)
                } else {
                    Circle()
                        .fill(anchorTint(for: flatIndex).opacity(0.34))
                        .frame(width: 7, height: 7)
                }
            }
            .frame(height: 68)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(phase != .input || isEntered)
        .accessibilityLabel("Row \(point.row + 1), column \(point.column + 1)")
        .accessibilityValue(entryIndex.map { "Selected \($0 + 1)" } ?? "Not selected")
        .accessibilityIdentifier("signal-cell-\(point.row)-\(point.column)")
    }

    private func cellFill(isHighlighted: Bool, isEntered: Bool) -> Color {
        if isHighlighted {
            return Tideglass.signal.opacity(0.90)
        }
        if isEntered {
            return Tideglass.seafoam.opacity(0.30)
        }
        return Tideglass.surface.opacity(0.70)
    }

    private func anchorTint(for index: Int) -> Color {
        switch index % 4 {
        case 0: return Tideglass.signal
        case 1: return Tideglass.seafoam
        case 2: return Tideglass.coral
        default: return Tideglass.muted
        }
    }

    private var progressSection: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                ForEach(1...3, id: \.self) { level in
                    Capsule()
                        .fill(level < run.level ? Tideglass.seafoam : (level == run.level ? Tideglass.signal : Tideglass.line))
                        .frame(height: 5)
                }
            }

            Text(displayStatusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)
                .frame(minHeight: 18)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: statusText)
        }
    }

    private var displayStatusText: String {
        if phase == .completed {
            return unlockError ?? "Rooms clear. Confirm to unlock YouTube."
        }
        return statusText
    }

    private var statusColor: Color {
        if unlockError != nil { return Tideglass.coral }
        if case .feedback(correct: false) = phase { return Tideglass.coral }
        if case .feedback(correct: true) = phase { return Tideglass.seafoam }
        return Tideglass.muted
    }

    private var controls: some View {
        ZStack {
            HStack(spacing: 10) {
                Button(phase == .completed && unlockError != nil ? "Close" : "Cancel") {
                    previewTask?.cancel()
                    onCancel()
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                .accessibilityIdentifier("cancel-signal-shift")

                if phase == .input {
                    Button("Replay signal") {
                        beginPreview()
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.signal))
                    .accessibilityIdentifier("replay-signal-path")
                }

                if phase == .input, !enteredPoints.isEmpty {
                    Button("Clear path") {
                        enteredPoints.removeAll()
                        statusText = "Path cleared. Try the transformation again."
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                    .accessibilityIdentifier("clear-signal-path")
                }

                Spacer()

                if phase == .ready {
                    Button("Show signal") {
                        beginPreview()
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                    .accessibilityIdentifier("start-signal-shift")
                } else if phase == .input {
                    Button("Tasks") { onChooseAnother() }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                        .accessibilityIdentifier("choose-another-signal-shift")
                } else if phase == .completed {
                    Button(unlockError == nil ? (isUnlocking ? "Unlocking…" : "Unlock YouTube") : "Close and retry") {
                        unlockError == nil ? onComplete() : onCancel()
                    }
                    .buttonStyle(GlassButtonStyle(
                        tint: unlockError == nil ? Tideglass.seafoam : Tideglass.coral,
                        isProminent: true
                    ))
                    .disabled(isUnlocking)
                    .accessibilityIdentifier("confirm-signal-shift-unlock")
                }
            }
        }
        .frame(minHeight: 44)
    }

    private func beginPreview() {
        previewTask?.cancel()
        enteredPoints.removeAll()
        highlightedPoint = nil
        phase = .preview
        statusText = "Hold the path…"
        let sequence = run.puzzle.sequence

        previewTask = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            for point in sequence {
                guard !Task.isCancelled else { return }
                highlightedPoint = point
                if !reduceMotion {
                    try? await Task.sleep(nanoseconds: 850_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
                highlightedPoint = nil
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
            guard !Task.isCancelled else { return }
            phase = .input
            statusText = "Your turn — \(run.puzzle.instruction)"
        }
    }

    private func choose(_ point: SignalGridPoint) {
        guard phase == .input, !enteredPoints.contains(point) else { return }
        enteredPoints.append(point)

        guard enteredPoints.count == run.puzzle.expectedSequence.count else {
            statusText = "\(enteredPoints.count) of \(run.puzzle.expectedSequence.count) positions"
            return
        }

        let answer = enteredPoints
        let livesBefore = run.livesRemaining
        let result = run.submit(answer)
        switch result {
        case .advanced(let nextLevel):
            phase = .feedback(correct: true)
            statusText = "Room clear. Rule switched for room \(nextLevel)."
            scheduleNextPreview()
        case .retry(let livesRemaining):
            phase = .feedback(correct: false)
            statusText = livesRemaining == livesBefore
                ? "Practice again — no life lost. You can replay the signal."
                : "Signal lost. \(livesRemaining) \(livesRemaining == 1 ? "life" : "lives") left."
            scheduleNextPreview()
        case .completed:
            phase = .completed
            statusText = "Rooms clear. Confirm to unlock YouTube."
        case .lockedOut:
            phase = .lockedOut
            statusText = "Three lives used. Enter your password again to retry."
            previewTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                onLockedOut()
            }
        }
    }

    private func scheduleNextPreview() {
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 350_000_000 : 900_000_000)
            guard !Task.isCancelled else { return }
            beginPreview()
        }
    }

    private static func randomSeed() -> UInt64 {
        var generator = SystemRandomNumberGenerator()
        return UInt64.random(in: UInt64.min...UInt64.max, using: &generator)
    }
}
