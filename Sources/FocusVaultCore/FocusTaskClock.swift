import Foundation

public enum FocusTaskClockState: Equatable {
    case ready
    case active
    case paused
    case completed
}

public enum FocusTaskClockError: Error, LocalizedError, Equatable {
    case invalidDuration

    public var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "Choose a task estimate between 1 and 240 minutes."
        }
    }
}

/// A deterministic, local task clock. Paused time never reduces the remainder.
public struct FocusTaskClock {
    public let durationSeconds: TimeInterval
    public private(set) var remainingSeconds: TimeInterval
    public private(set) var state: FocusTaskClockState

    private var lastActiveDate: Date?

    public init(minutes: Int) throws {
        guard (1...240).contains(minutes) else {
            throw FocusTaskClockError.invalidDuration
        }

        durationSeconds = TimeInterval(minutes * 60)
        remainingSeconds = TimeInterval(minutes * 60)
        state = .ready
        lastActiveDate = nil
    }

    public var progress: Double {
        guard durationSeconds > 0 else { return 1 }
        return min(1, max(0, 1 - (remainingSeconds / durationSeconds)))
    }

    public var remainingWholeSeconds: Int {
        max(0, Int(ceil(remainingSeconds)))
    }

    @discardableResult
    public mutating func start(at date: Date) -> Bool {
        guard state == .ready || state == .completed else { return false }
        remainingSeconds = durationSeconds
        state = .active
        lastActiveDate = date
        return true
    }

    public mutating func update(at date: Date) {
        guard state == .active, let lastActiveDate else { return }

        let elapsed = max(0, date.timeIntervalSince(lastActiveDate))
        remainingSeconds = max(0, remainingSeconds - elapsed)
        self.lastActiveDate = date

        if remainingSeconds == 0 {
            state = .completed
            self.lastActiveDate = nil
        }
    }

    @discardableResult
    public mutating func pause(at date: Date) -> Bool {
        guard state == .active else { return false }
        update(at: date)
        guard state == .active else { return false }
        state = .paused
        lastActiveDate = nil
        return true
    }

    @discardableResult
    public mutating func resume(at date: Date) -> Bool {
        guard state == .paused, remainingSeconds > 0 else { return false }
        state = .active
        lastActiveDate = date
        return true
    }

    @discardableResult
    public mutating func stop(at date: Date) -> Bool {
        guard state == .active || state == .paused else { return false }
        if state == .active {
            update(at: date)
        }
        guard state == .active || state == .paused else { return false }
        state = .ready
        remainingSeconds = durationSeconds
        lastActiveDate = nil
        return true
    }
}
