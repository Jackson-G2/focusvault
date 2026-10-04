import SwiftUI
import VaultyCore

enum SessionDialState {
    case ready
    case active
    case paused
}

struct SessionDial: View {
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

struct FocusPulse: View {
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

struct CompletionMark: View {
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
